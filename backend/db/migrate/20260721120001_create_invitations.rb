# frozen_string_literal: true

# workspace-invitations §"Entidade Convite" (tarefa 1.2 / D-INV-1, D-INV-4).
#
# Tudo que a invariante 7 (§4.1) pede está aqui EM CONSTRAINT, não em model:
#
#   - `role` é o enum `invitation_role` com EXATAMENTE 'view' e 'edit'. `owner`
#     não é valor representável: `INSERT ... role='owner'` falha com "invalid
#     input value for enum", sem passar por validação de model.
#   - a FK COMPOSTA (workspace_id, created_by_person_id) → people (workspace_id, id)
#     impede convite cujo criador pertence a OUTRO workspace. Ela não sabe se o
#     criador é `owner` — isso é a InvitationPolicy (D-INV-4) e tem teste próprio.
#   - `CHECK (email = lower(email))` fecha a porta do console: um e-mail em
#     maiúsculas nunca casaria na comparação literal da invariante 6, então ele
#     não pode sequer existir. A normalização mora na ESCRITA (legado compara com
#     `request.auth.token.email.lower()` sem normalizar na leitura — D-INV-3).
#   - `chk_invitations_consumption` torna o estado meio-consumido impossível:
#     `used_at` e `used_by_user_id` são preenchidos juntos ou não são (D-INV-2,
#     terceira camada).
#
# `expires_at` é NOT NULL. O legado tolerava `expiresAt` ausente
# (`firestore.rules` L33) e aqueles convites NUNCA expiravam; esse bug não é
# portado — convite sem expiração não é representável.
class CreateInvitations < ActiveRecord::Migration[8.0]
  def up
    execute(<<~SQL)
      CREATE TYPE invitation_role AS ENUM ('view', 'edit');

      CREATE TABLE invitations (
        id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        workspace_id         uuid NOT NULL REFERENCES workspaces (id),
        token                text NOT NULL,
        email                text NOT NULL,
        role                 invitation_role NOT NULL,
        created_by_person_id uuid NOT NULL,
        expires_at           timestamptz NOT NULL DEFAULT (now() + interval '7 days'),
        used_at              timestamptz NULL,
        used_by_user_id      uuid NULL REFERENCES users (id),
        created_at           timestamptz NOT NULL DEFAULT now(),
        updated_at           timestamptz NOT NULL DEFAULT now(),

        CONSTRAINT chk_invitations_email_lowercase CHECK (email = lower(email)),
        CONSTRAINT chk_invitations_email_length    CHECK (char_length(email) <= 254),
        CONSTRAINT chk_invitations_consumption CHECK (
          (used_at IS NULL     AND used_by_user_id IS NULL)
          OR
          (used_at IS NOT NULL AND used_by_user_id IS NOT NULL)
        ),

        CONSTRAINT fk_invitations_creator_in_workspace
          FOREIGN KEY (workspace_id, created_by_person_id)
          REFERENCES people (workspace_id, id)
      );

      -- O token é a chave pública opaca que viaja na URL: unicidade no banco,
      -- não só no gerador (D-INV-1).
      CREATE UNIQUE INDEX index_invitations_on_token ON invitations (token);

      -- Índice começando por workspace_id: exigido pela guarda de esquema de
      -- tenancy (custo de RLS) e usado pela listagem de pendentes.
      CREATE INDEX index_invitations_on_workspace_id_and_created_at
        ON invitations (workspace_id, created_at DESC);

      -- Pergunta em aberto (3) do design.md, decidida: NÃO se acumulam dois
      -- convites pendentes para o mesmo e-mail no mesmo workspace. O legado
      -- permitia N e o dono ficava sem saber qual link vale.
      CREATE UNIQUE INDEX index_invitations_pending_unique_per_email
        ON invitations (workspace_id, email) WHERE used_at IS NULL;
    SQL
  end

  def down
    execute(<<~SQL)
      DROP TABLE IF EXISTS invitations;
      DROP TYPE  IF EXISTS invitation_role;
    SQL
  end
end
