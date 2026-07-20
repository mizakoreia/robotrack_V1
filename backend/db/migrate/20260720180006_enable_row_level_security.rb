# frozen_string_literal: true

# tenant-isolation §"Row Level Security" / design D-1, D-2 (tarefa 3.1).
#
# ENABLE + FORCE em people, workspaces e memberships. FORCE não é opcional: sem
# ele o DONO das tabelas (robotrack_migrator, quem roda as migrations) ignoraria
# a política, e bastaria a app conectar com essa credencial para a RLS ser
# decorativa.
#
# `people` (e toda tabela de domínio futura) usa a política PURA de tenant.
# `workspaces` e `memberships` são tabelas de CONTROLE: precisam ser legíveis
# ANTES de haver um tenant escolhido (para listar os workspaces do usuário), por
# isso combinam `app.current_workspace_id` com `app.current_user_id`. O WITH CHECK
# delas é SÓ a cláusula de workspace/id — inserir num workspace que não é o
# corrente é proibido, mesmo que o USING deixe ler.
#
# `NULLIF(current_setting(...), '')::uuid`: sem contexto, `current_setting(.., true)`
# devolve NULL (ou '' numa conexão já tocada); NULLIF normaliza para NULL, a
# comparação vira NULL, e NULL não é TRUE — nenhuma linha passa. Fail-closed por
# construção, não por `if`.
class EnableRowLevelSecurity < ActiveRecord::Migration[8.0]
  def up
    execute(<<~SQL)
      -- people e demais tabelas de domínio: política pura de tenant.
      ALTER TABLE people ENABLE ROW LEVEL SECURITY;
      ALTER TABLE people FORCE  ROW LEVEL SECURITY;
      CREATE POLICY tenant_isolation ON people
        USING      (workspace_id = NULLIF(current_setting('app.current_workspace_id', true), '')::uuid)
        WITH CHECK (workspace_id = NULLIF(current_setting('app.current_workspace_id', true), '')::uuid);

      -- workspaces: tenant corrente, o que possuo, ou onde sou membro.
      ALTER TABLE workspaces ENABLE ROW LEVEL SECURITY;
      ALTER TABLE workspaces FORCE  ROW LEVEL SECURITY;
      CREATE POLICY tenant_isolation ON workspaces
        USING (
          id            = NULLIF(current_setting('app.current_workspace_id', true), '')::uuid
          OR owner_user_id = NULLIF(current_setting('app.current_user_id', true), '')::uuid
          OR EXISTS (
            SELECT 1 FROM memberships m
            WHERE m.workspace_id = workspaces.id
              AND m.user_id = NULLIF(current_setting('app.current_user_id', true), '')::uuid
          )
        )
        WITH CHECK (id = NULLIF(current_setting('app.current_workspace_id', true), '')::uuid);

      -- memberships: tenant corrente OU sempre as minhas próprias linhas.
      ALTER TABLE memberships ENABLE ROW LEVEL SECURITY;
      ALTER TABLE memberships FORCE  ROW LEVEL SECURITY;
      CREATE POLICY tenant_isolation ON memberships
        USING (
          workspace_id = NULLIF(current_setting('app.current_workspace_id', true), '')::uuid
          OR user_id   = NULLIF(current_setting('app.current_user_id', true), '')::uuid
        )
        WITH CHECK (workspace_id = NULLIF(current_setting('app.current_workspace_id', true), '')::uuid);
    SQL
  end

  def down
    execute(<<~SQL)
      DROP POLICY IF EXISTS tenant_isolation ON people;
      DROP POLICY IF EXISTS tenant_isolation ON workspaces;
      DROP POLICY IF EXISTS tenant_isolation ON memberships;
      ALTER TABLE people      NO FORCE ROW LEVEL SECURITY;
      ALTER TABLE people      DISABLE  ROW LEVEL SECURITY;
      ALTER TABLE workspaces  NO FORCE ROW LEVEL SECURITY;
      ALTER TABLE workspaces  DISABLE  ROW LEVEL SECURITY;
      ALTER TABLE memberships NO FORCE ROW LEVEL SECURITY;
      ALTER TABLE memberships DISABLE  ROW LEVEL SECURITY;
    SQL
  end
end
