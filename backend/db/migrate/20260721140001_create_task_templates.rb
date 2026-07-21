# frozen_string_literal: true

# task-catalog 1.4–1.6 (§1.1, §1.2, §3.9, D2, D-TC-1, D-TC-2).
#
# O catálogo é PROPRIEDADE do workspace (§3.9 permite editar e excluir qualquer
# item), então `workspace_id NOT NULL` + RLS forçada, como toda tabela de
# domínio desde a Onda 1.
#
# `app_filters text[]` com CHECK de domínio: a lista aceita os 6 valores da §1.2
# MAIS `'Todas'` — que o importador legado precisa gravar (§1.4 item 3). O
# conjunto vazio passa por construção (`'{}' <@ qualquer` é TRUE), que é
# justamente o estado normalizado de "vale para todo robô" (D-TC-2).
#
# `weight numeric CHECK (> 0)`: peso zero tornaria a tarefa invisível ao cálculo
# ponderado da §2.1 sem sumir da tela — pior que não existir.
#
# O tipo enum `robot_application` NÃO é criado: `robots.application` já é
# `text` + CHECK dos 6 literais desde `commissioning-hierarchy` (D-H10), e as
# duas changes concordam na invariante. Ver EXECUCAO.md, decisão 1.
class CreateTaskTemplates < ActiveRecord::Migration[8.0]
  def up
    execute(<<~SQL)
      CREATE TABLE task_templates (
        id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        workspace_id uuid NOT NULL REFERENCES workspaces (id),
        cat          text NOT NULL,
        "desc"       text NOT NULL,
        weight       numeric NOT NULL DEFAULT 1,
        app_filters  text[] NOT NULL DEFAULT '{}',
        created_at   timestamptz NOT NULL DEFAULT now(),
        updated_at   timestamptz NOT NULL DEFAULT now(),

        CONSTRAINT chk_task_templates_cat  CHECK (length(btrim(cat)) BETWEEN 1 AND 120),
        CONSTRAINT chk_task_templates_desc CHECK (length(btrim("desc")) BETWEEN 1 AND 200),
        CONSTRAINT chk_task_templates_weight CHECK (weight > 0),
        CONSTRAINT chk_task_templates_app_filters CHECK (
          app_filters <@ ARRAY[
            'Misto / Geral','Solda Ponto','Solda MIG','Handling','Sealing','Outros','Todas'
          ]::text[]
        ),
        CONSTRAINT uq_task_templates_id_workspace UNIQUE (id, workspace_id)
      );

      -- Listagem da tela de configurações (§3.9), sempre por workspace.
      CREATE INDEX index_task_templates_on_workspace_cat_desc
        ON task_templates (workspace_id, cat, "desc");

      -- §3.9: duas descrições iguais (a menos de espaços/caixa) no mesmo
      -- workspace são erro de digitação, não intenção — e a sincronização
      -- retroativa (§2.6) dedup por esta mesma normalização.
      CREATE UNIQUE INDEX index_task_templates_on_workspace_lower_desc
        ON task_templates (workspace_id, lower(btrim("desc")));

      ALTER TABLE task_templates ENABLE ROW LEVEL SECURITY;
      ALTER TABLE task_templates FORCE  ROW LEVEL SECURITY;

      CREATE POLICY tenant_isolation ON task_templates
        USING (workspace_id = NULLIF(current_setting('app.current_workspace_id', true), '')::uuid)
        WITH CHECK (workspace_id = NULLIF(current_setting('app.current_workspace_id', true), '')::uuid);
    SQL
  end

  def down
    execute('DROP TABLE IF EXISTS task_templates;')
  end
end
