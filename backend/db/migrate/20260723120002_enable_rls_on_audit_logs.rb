# frozen_string_literal: true

# audit-log G1 (§4.1 inv. 3, D2, Decisão 1 — camada 3 de imutabilidade + isolamento).
#
# RLS com policies APENAS de SELECT e INSERT — NENHUMA de UPDATE/DELETE (ausência =
# negação por omissão, a 3ª negação da Decisão 1). ATENÇÃO ao particionamento: RLS
# habilitada só no PARENT NÃO protege um `SELECT`/`INSERT` DIRETO numa partição —
# as partições nascem com `relrowsecurity=f`. Como o papel de app tem SELECT/INSERT
# nas partições (grant de ALL TABLES), sem RLS por partição um `SELECT FROM
# audit_logs_2026_07` vazaria cross-tenant. Logo: a função `secure_audit_partition`
# aplica ENABLE+FORCE RLS + as duas policies a CADA partição, e é reusada pelo job
# de manutenção de partições (G7) para as futuras. O `schema_guard` (tenant-
# isolation) exige isso de toda tabela de domínio, partições inclusive.
class EnableRlsOnAuditLogs < ActiveRecord::Migration[8.0]
  def up
    execute(<<~SQL)
      ALTER TABLE audit_logs ENABLE ROW LEVEL SECURITY;
      ALTER TABLE audit_logs FORCE  ROW LEVEL SECURITY;

      CREATE POLICY tenant_isolation ON audit_logs FOR SELECT
        USING (workspace_id = NULLIF(current_setting('app.current_workspace_id', true), '')::uuid);

      CREATE POLICY tenant_isolation_insert ON audit_logs FOR INSERT
        WITH CHECK (workspace_id = NULLIF(current_setting('app.current_workspace_id', true), '')::uuid);

      -- Reusada pela migration e pelo job de partições (G7). Idempotente: ignora
      -- policy já existente. `%s` = a partição (regclass); o corpo das policies é
      -- dollar-quoted ($fmt$) para não escapar aspas simples.
      CREATE OR REPLACE FUNCTION secure_audit_partition(part regclass) RETURNS void AS $fn$
      BEGIN
        EXECUTE format('ALTER TABLE %s ENABLE ROW LEVEL SECURITY', part);
        EXECUTE format('ALTER TABLE %s FORCE ROW LEVEL SECURITY', part);
        BEGIN
          EXECUTE format($fmt$CREATE POLICY tenant_isolation ON %s FOR SELECT
            USING (workspace_id = NULLIF(current_setting('app.current_workspace_id', true), '')::uuid)$fmt$, part);
        EXCEPTION WHEN duplicate_object THEN NULL;
        END;
        BEGIN
          EXECUTE format($fmt$CREATE POLICY tenant_isolation_insert ON %s FOR INSERT
            WITH CHECK (workspace_id = NULLIF(current_setting('app.current_workspace_id', true), '')::uuid)$fmt$, part);
        EXCEPTION WHEN duplicate_object THEN NULL;
        END;
      END;
      $fn$ LANGUAGE plpgsql;

      -- Aplica a todas as partições existentes (mês corrente + 3 + DEFAULT).
      DO $do$
      DECLARE part regclass;
      BEGIN
        FOR part IN
          SELECT inhrelid::regclass FROM pg_inherits
          WHERE inhparent = 'audit_logs'::regclass
        LOOP
          PERFORM secure_audit_partition(part);
        END LOOP;
      END
      $do$;
    SQL
  end

  def down
    execute(<<~SQL)
      DO $do$
      DECLARE part regclass;
      BEGIN
        FOR part IN
          SELECT inhrelid::regclass FROM pg_inherits
          WHERE inhparent = 'audit_logs'::regclass
        LOOP
          EXECUTE format('DROP POLICY IF EXISTS tenant_isolation_insert ON %s', part);
          EXECUTE format('DROP POLICY IF EXISTS tenant_isolation ON %s', part);
          EXECUTE format('ALTER TABLE %s NO FORCE ROW LEVEL SECURITY', part);
          EXECUTE format('ALTER TABLE %s DISABLE ROW LEVEL SECURITY', part);
        END LOOP;
      END
      $do$;

      DROP FUNCTION IF EXISTS secure_audit_partition(regclass);
      DROP POLICY IF EXISTS tenant_isolation_insert ON audit_logs;
      DROP POLICY IF EXISTS tenant_isolation ON audit_logs;
      ALTER TABLE audit_logs NO FORCE ROW LEVEL SECURITY;
      ALTER TABLE audit_logs DISABLE ROW LEVEL SECURITY;
    SQL
  end
end
