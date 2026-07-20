# frozen_string_literal: true

# workspace-membership §"Dono não é membro" / §1.1 (tarefa 2.4).
#
# O dono do workspace NÃO é membro. Sem esta trigger, `INSERT INTO memberships`
# com `user_id = owner_user_id` criaria dois papéis conflitantes para a mesma
# pessoa (a membership `edit`/`view` mais o `owner` derivado). A trigger levanta
# exceção em vez de deixar o dado inconsistente nascer — invariante no BANCO, não
# no model, que um console contornaria.
class AddMembershipsOwnerIsNotMemberTrigger < ActiveRecord::Migration[8.0]
  def up
    execute(<<~SQL)
      CREATE FUNCTION memberships_owner_is_not_member()
      RETURNS trigger AS $$
      BEGIN
        IF NEW.user_id = (
          SELECT owner_user_id FROM workspaces WHERE id = NEW.workspace_id
        ) THEN
          RAISE EXCEPTION
            'o dono do workspace não pode ser membro (§1.1): user_id=%', NEW.user_id;
        END IF;
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;

      CREATE TRIGGER memberships_owner_is_not_member
        BEFORE INSERT OR UPDATE ON memberships
        FOR EACH ROW EXECUTE FUNCTION memberships_owner_is_not_member();
    SQL
  end

  def down
    execute(<<~SQL)
      DROP TRIGGER IF EXISTS memberships_owner_is_not_member ON memberships;
      DROP FUNCTION IF EXISTS memberships_owner_is_not_member();
    SQL
  end
end
