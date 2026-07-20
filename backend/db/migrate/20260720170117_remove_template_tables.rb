# frozen_string_literal: true

# Descarta as 24 tabelas dos módulos que não pertencem ao RoboTrack, removidos
# em código nos grupos G3–G6.
#
# A tarefa 7.2 falava em 22 tabelas, sem login_codes e login_attempts. Elas
# entram aqui porque G6 deletou seus models: mantê-las seria deixar duas tabelas
# órfãs sem model — exatamente o drift que 7.5 exige provar eliminado. O
# design.md já previa que elas "caem na Fase 4".
#
# Dez delas (plans, plan_features, plan_feature_assignments,
# plan_feature_permissions, purchases, subscriptions, orders, order_items,
# items, categories) existiam em db/schema.rb SEM arquivo de migration e sem
# model: `rails db:migrate` do zero nunca reproduzia o schema. Reconstruir a
# história — escrever os create_table que faltam só para depois derrubá-los —
# seria arqueologia pura, então o schema.rb é tratado como fonte da verdade e
# esta migration só descarta (design §D-F).
#
# A ordem é filhas -> mães para que `force: :cascade` seja rede de segurança e
# não o mecanismo.
class RemoveTemplateTables < ActiveRecord::Migration[8.0]
  TABLES = %w[
    plan_feature_assignments
    plan_feature_permissions
    plan_features
    plans

    order_items
    orders
    items
    categories
    purchases
    subscriptions

    permission_audit_logs
    permission_conflicts
    user_permissions
    permissions

    lead_messages
    leads
    operations

    polemk_chat_messages
    polemk_instance_groups
    polemk_instances
    polemk_webhooks

    client_applications

    login_codes
    login_attempts
  ].freeze

  def up
    TABLES.each do |table|
      drop_table(table, force: :cascade) if table_exists?(table)
    end
  end

  # Sem down que recrie estrutura: um down que devolve tabelas vazias dá falsa
  # sensação de reversibilidade — em desenvolvimento o que se quer de volta ao
  # reverter é o DADO, e dado só volta pelo dump.
  def down
    raise ActiveRecord::IrreversibleMigration,
          'RemoveTemplateTables é irreversível por design. O caminho de rollback é ' \
          'restaurar o dump verificado em backend/tmp/backups/ com ' \
          '`pg_restore -d <banco> backend/tmp/backups/pre-seal-<AAAAMMDD-HHMM>.dump`.'
  end
end
