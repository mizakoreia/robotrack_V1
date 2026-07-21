# frozen_string_literal: true

# workspace-invitations §"Consumo atômico" (tarefa 1.3 / D-INV-2, segunda camada).
#
# `memberships.invitation_id` já existe desde `CreateMemberships` (Onda 1), mas
# sem FK e sem unicidade. Esta migration é ADITIVA e fecha as duas pontas:
#
#   - `ON DELETE RESTRICT`: um convite consumido NÃO pode ser apagado enquanto a
#     membership que ele originou existir. Essa referência é a prova auditável de
#     por que aquela pessoa tem acesso, e é o que faz o job de expurgo (D-INV-9)
#     precisar preservar os consumidos.
#   - índice único PARCIAL: dois `INSERT` de membership com o mesmo
#     `invitation_id` colidem, mesmo que alguém contorne o service. As
#     memberships migradas do legado nascem com `invitation_id NULL` e não
#     colidem entre si — a cláusula parcial documenta essa intenção (NULLs já são
#     distintos num índice único do Postgres) e mantém o índice pequeno.
class LinkMembershipsToInvitations < ActiveRecord::Migration[8.0]
  def up
    execute(<<~SQL)
      ALTER TABLE memberships
        ADD CONSTRAINT fk_memberships_invitation
        FOREIGN KEY (invitation_id) REFERENCES invitations (id) ON DELETE RESTRICT;

      CREATE UNIQUE INDEX idx_memberships_one_per_invitation
        ON memberships (invitation_id) WHERE invitation_id IS NOT NULL;
    SQL
  end

  def down
    execute(<<~SQL)
      DROP INDEX IF EXISTS idx_memberships_one_per_invitation;
      ALTER TABLE memberships DROP CONSTRAINT IF EXISTS fk_memberships_invitation;
    SQL
  end
end
