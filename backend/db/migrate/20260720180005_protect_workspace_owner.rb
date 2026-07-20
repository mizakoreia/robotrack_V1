# frozen_string_literal: true

# workspace-core §"Imutabilidade do dono" / §4.1 inv. 5 (tarefa 2.5).
#
# Duas camadas, porque nenhuma sozinha cobre todos os papéis de banco:
#
# 1. Privilégio de coluna para robotrack_app. NÃO basta `REVOKE UPDATE
#    (owner_user_id)`: quando o papel tem UPDATE em nível de TABELA (concedido por
#    ALTER DEFAULT PRIVILEGES em db/roles.sql), o privilégio efetivo é a UNIÃO do
#    de tabela com o de coluna — o revoke de coluna não subtrai nada. Por isso
#    revogamos o UPDATE de tabela e concedemos de volta só as colunas mutáveis
#    (name, updated_at). Efeito observável idêntico ao pedido pela spec:
#    `robotrack_app` recebe `permission denied for column owner_user_id`.
#
# 2. Trigger BEFORE UPDATE, que cobre robotrack_migrator e qualquer conexão
#    administrativa (que têm privilégio de coluna e ignorariam a camada 1).
class ProtectWorkspaceOwner < ActiveRecord::Migration[8.0]
  def up
    execute(<<~SQL)
      REVOKE UPDATE ON workspaces FROM robotrack_app;
      GRANT  UPDATE (name, updated_at) ON workspaces TO robotrack_app;

      CREATE FUNCTION workspaces_owner_immutable()
      RETURNS trigger AS $$
      BEGIN
        IF NEW.owner_user_id IS DISTINCT FROM OLD.owner_user_id THEN
          RAISE EXCEPTION
            'owner_user_id do workspace é imutável (§4.1 inv. 5)';
        END IF;
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;

      CREATE TRIGGER workspaces_owner_immutable
        BEFORE UPDATE ON workspaces
        FOR EACH ROW EXECUTE FUNCTION workspaces_owner_immutable();
    SQL
  end

  def down
    execute(<<~SQL)
      DROP TRIGGER IF EXISTS workspaces_owner_immutable ON workspaces;
      DROP FUNCTION IF EXISTS workspaces_owner_immutable();
      GRANT UPDATE ON workspaces TO robotrack_app;
    SQL
  end
end
