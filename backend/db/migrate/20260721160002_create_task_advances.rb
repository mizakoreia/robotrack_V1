# frozen_string_literal: true

# progress-advances G1 / Migration A (§1.1, D-TS, D-ORD, D-CMT, D-LEG, D2).
#
# A trilha append-only do comissionamento. Invariantes NO BANCO, não no model:
# faixa 0–100, comentário obrigatório abaixo de 100 (isento para `legacy`),
# comprimento do comentário, autor nulo SÓ se `legacy`, e `recorded_at` dentro da
# janela de skew (rede contra qualquer porta de escrita além do service).
#
# Coerência de workspace por FK COMPOSTA (EXECUCAO decisão 3), não trigger:
# `(task_id, workspace_id) → tasks(id, workspace_id)` garante que o avanço e a
# tarefa são do MESMO workspace; `(by, workspace_id) → people(workspace_id, id)`
# faz o mesmo para o autor (nula quando `by` é NULL — entrada legada). Ambas
# `ON DELETE RESTRICT`: a trilha nunca é apagada em cascata (D-IMUT).
#
# `recorded_at` é a hora que a PESSOA agiu (cliente, D-TS); `created_at` é quando
# o servidor persistiu. A leitura exibe `recorded_at`; o índice de trilha (D-ORD)
# ordena determinísticamente com o `id` como terceiro critério de desempate.
class CreateTaskAdvances < ActiveRecord::Migration[8.0]
  def up
    execute(<<~SQL)
      CREATE TABLE task_advances (
        id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        workspace_id         uuid NOT NULL REFERENCES workspaces (id),
        task_id              uuid NOT NULL,
        "by"                 uuid NULL,
        author_name_snapshot text NOT NULL,
        from_progress        smallint NOT NULL,
        to_progress          smallint NOT NULL,
        comment              text NULL,
        legacy               boolean NOT NULL DEFAULT false,
        recorded_at          timestamptz NOT NULL,
        recorded_at_adjusted boolean NOT NULL DEFAULT false,
        created_at           timestamptz NOT NULL DEFAULT now(),

        CONSTRAINT chk_ta_from_range CHECK (from_progress BETWEEN 0 AND 100),
        CONSTRAINT chk_ta_to_range   CHECK (to_progress BETWEEN 0 AND 100),
        CONSTRAINT chk_ta_comment_required
          CHECK (to_progress = 100 OR legacy OR (comment IS NOT NULL AND btrim(comment) <> '')),
        CONSTRAINT chk_ta_comment_len CHECK (comment IS NULL OR char_length(comment) <= 1000),
        CONSTRAINT chk_ta_author_null_only_legacy CHECK ("by" IS NOT NULL OR legacy),
        CONSTRAINT chk_ta_author_name CHECK (length(btrim(author_name_snapshot)) BETWEEN 1 AND 200),
        CONSTRAINT chk_ta_recorded_at CHECK (recorded_at <= created_at + interval '10 minutes'),

        CONSTRAINT fk_ta_task_same_workspace
          FOREIGN KEY (task_id, workspace_id)
          REFERENCES tasks (id, workspace_id) ON DELETE RESTRICT,
        CONSTRAINT fk_ta_author_same_workspace
          FOREIGN KEY (workspace_id, "by")
          REFERENCES people (workspace_id, id) ON DELETE RESTRICT
      );

      -- Leitura da trilha (D-ORD): mais recentes primeiro, com id de desempate.
      CREATE INDEX index_task_advances_trail
        ON task_advances (task_id, recorded_at DESC, created_at DESC, id DESC);

      -- Índice liderado por workspace_id (guarda de tenancy + custo de RLS).
      CREATE INDEX index_task_advances_on_workspace_task
        ON task_advances (workspace_id, task_id);
    SQL
  end

  def down
    execute('DROP TABLE IF EXISTS task_advances;')
  end
end
