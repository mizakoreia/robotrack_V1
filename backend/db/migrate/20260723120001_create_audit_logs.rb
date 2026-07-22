# frozen_string_literal: true

# audit-log G1 (§1.1, §2.8, D1/D2/D4/D6/D7, Decisão 2/4/6/7). A trilha de auditoria
# append-only por workspace.
#
# PARTICIONADA por RANGE(ts) (Decisão 2 — retenção por DDL, não por DELETE): a PK
# tem de conter a chave de partição, logo é `(ts, id)`, com `id` uuid cliente-
# gerável (D1). A unicidade de `id` repousa no uuid v4 (auditada pelo job mensal,
# G7); nada referencia `audit_logs`, então a PK composta não vaza para outro esquema.
#
# SEM FK para hierarquia (Decisão 7/D12) — as referências vivem em `payload` como
# uuid + texto denormalizado, para o log SOBREVIVER ao cascade delete do reset de
# fábrica. A FK para `workspaces` é `ON DELETE RESTRICT`: o log impede a remoção da
# linha do workspace (D12 já garante que o reset não a remove). Autor por
# `by_person_id` (FK simples `ON DELETE SET NULL`, mesmo padrão de
# `cells.updated_by_person_id`) + `by_name` snapshot imutável (D6/D10): remover a
# `Person` não apaga quem agiu.
#
# `msg` e `ts_local` são o texto RENDERIZADO e CONGELADO no INSERT (Decisão 4); a
# leitura os usa verbatim. `event_type`/`format_version`/`payload` guardam os dados
# para leitura por máquina. `def down` é IrreversibleMigration com linhas (Decisão 2 /
# plano de migração 5): depois do 1º registro em produção, reverter não é `DROP TABLE`.
class CreateAuditLogs < ActiveRecord::Migration[8.0]
  def up
    execute(<<~SQL)
      CREATE TABLE audit_logs (
        id             uuid NOT NULL DEFAULT gen_random_uuid(),
        workspace_id   uuid NOT NULL,
        event_type     text NOT NULL,
        format_version integer NOT NULL DEFAULT 1,
        msg            text NOT NULL,
        ts             timestamptz NOT NULL DEFAULT now(),
        ts_local       text NOT NULL,
        by_person_id   uuid NULL,
        by_name        text NOT NULL,
        payload        jsonb NOT NULL DEFAULT '{}'::jsonb,

        CONSTRAINT audit_logs_pkey PRIMARY KEY (ts, id),
        CONSTRAINT chk_audit_by_name CHECK (length(btrim(by_name)) BETWEEN 1 AND 200),
        CONSTRAINT chk_audit_msg CHECK (btrim(msg) <> ''),
        CONSTRAINT chk_audit_event_type
          CHECK (event_type IN ('task_completed', 'workspace_reset')),
        CONSTRAINT fk_audit_workspace
          FOREIGN KEY (workspace_id) REFERENCES workspaces (id) ON DELETE RESTRICT,
        CONSTRAINT fk_audit_author
          FOREIGN KEY (by_person_id) REFERENCES people (id) ON DELETE SET NULL
      ) PARTITION BY RANGE (ts);

      -- Índice de leitura do modal (Decisão 9): por workspace, mais recente 1º.
      -- No PARENT particionado — cada partição herda uma cópia.
      CREATE INDEX index_audit_logs_on_workspace_ts
        ON audit_logs (workspace_id, ts DESC);
    SQL

    create_range_partitions
    execute("CREATE TABLE audit_logs_default PARTITION OF audit_logs DEFAULT;")
  end

  def down
    if data_exists?
      raise ActiveRecord::IrreversibleMigration,
            'audit_logs tem registros: reverter não é DROP TABLE (audit-log Decisão 2). ' \
            'A reversão se dá pelo caminho de arquivamento (retenção).'
    end
    execute('DROP TABLE IF EXISTS audit_logs;')
  end

  private

  # Mês corrente + 3 seguintes (§2.2). O job mensal (G7) cria as futuras; a
  # partição DEFAULT é a rede enquanto isso. Faixas computadas em Ruby porque a
  # migration roda uma vez e o structure.sql congela as tabelas resultantes.
  def create_range_partitions
    base = Time.current.utc.beginning_of_month
    (0..3).each do |i|
      from = base.advance(months: i)
      to   = base.advance(months: i + 1)
      execute(<<~SQL)
        CREATE TABLE audit_logs_#{from.strftime('%Y_%m')} PARTITION OF audit_logs
          FOR VALUES FROM ('#{from.strftime('%Y-%m-%d')}') TO ('#{to.strftime('%Y-%m-%d')}');
      SQL
    end
  end

  def data_exists?
    select_value('SELECT EXISTS (SELECT 1 FROM audit_logs LIMIT 1)')
  rescue ActiveRecord::StatementInvalid
    false
  end
end
