# frozen_string_literal: true

# send-feedback G1 — canal de feedback do beta: cada linha é uma mensagem livre
# que um MEMBRO do workspace enviou de dentro do app, com CONTEXTO técnico
# capturado automaticamente (rota, workspace, papel, user-agent) para o dono ler
# com situação, não só o texto solto.
#
# `workspace_id` NOT NULL (DIVERGÊNCIA registrada do brief "nullable"): a RLS
# FORÇADA torna uma linha com `workspace_id IS NULL` invisível a QUALQUER contexto
# (`NULL = <uuid>` nunca é verdade) e o WITH CHECK recusaria o INSERT sem GUC —
# nullable seria um cemitério de dados que o dono nunca leria. O `workspace_id` é
# sempre derivado do contexto de tenant (header `X-Workspace-Id` → GUC), NUNCA do
# corpo do cliente. O dono lê os feedbacks do PRÓPRIO workspace (RLS), que é onde
# os beta testers convidados operam.
#
# `user_id` opcional, FK GLOBAL a `users` com ON DELETE SET NULL: identidade
# durável do autor que sobrevive ao arquivamento da `Person` do workspace. NÃO uso
# `person_id` com FK composta a `people`: a FK composta não pode SET NULL (o
# `workspace_id` é NOT NULL) e CASCADE apagaria o feedback ao arquivar a pessoa —
# contraria "preserve o histórico". A segurança de tenant do autor já é garantida
# na escrita (o servidor grava `user_id` do bearer; o cliente não o fornece).
#
# `context` jsonb (objeto) para o pacote de contexto automático; `message` com
# CHECK de tamanho (1..4000) — barreira de spam/abuso no banco, além do rate-limit.
#
# RLS FORÇADA no idioma exato das demais tabelas de tenant. GRANT ao `robotrack_app`
# é automático (default-privileges do `robotrack_migrator`, `db/roles.sql`) — tabela
# mutável, sem REVOKE de imutabilidade. Reversão: `DROP TABLE` — barata.
class CreateFeedbacks < ActiveRecord::Migration[8.0]
  def up
    execute(<<~SQL)
      CREATE TABLE feedbacks (
        id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        workspace_id  uuid NOT NULL REFERENCES workspaces (id) ON DELETE CASCADE,
        user_id       uuid REFERENCES users (id) ON DELETE SET NULL,
        message       text  NOT NULL,
        context       jsonb NOT NULL DEFAULT '{}'::jsonb,
        created_at    timestamptz NOT NULL DEFAULT now(),

        CONSTRAINT chk_feedback_message_len
          CHECK (char_length(btrim(message)) BETWEEN 1 AND 4000),
        CONSTRAINT chk_feedback_context_object
          CHECK (jsonb_typeof(context) = 'object')
      );

      -- Índice liderado por workspace_id: guarda de tenancy + custo de RLS.
      CREATE INDEX index_feedbacks_on_workspace_id
        ON feedbacks (workspace_id);

      -- A leitura do dono é "os do meu workspace, mais recentes primeiro".
      CREATE INDEX index_feedbacks_on_workspace_created
        ON feedbacks (workspace_id, created_at DESC);

      ALTER TABLE feedbacks ENABLE ROW LEVEL SECURITY;
      ALTER TABLE feedbacks FORCE  ROW LEVEL SECURITY;

      CREATE POLICY tenant_isolation ON feedbacks
        USING (workspace_id = NULLIF(current_setting('app.current_workspace_id', true), '')::uuid)
        WITH CHECK (workspace_id = NULLIF(current_setting('app.current_workspace_id', true), '')::uuid);
    SQL
  end

  def down
    execute('DROP TABLE IF EXISTS feedbacks;')
  end
end
