# frozen_string_literal: true

# identity-and-auth 1.3 — migration DESTRUTIVA, reversível (up/down).
#
# Precedida OBRIGATORIAMENTE do dump lógico de `users` (bin/backup_users, 1.1).
#
#   - `users.jti` + índice único saem (D4.1): a coluna é a assinatura da
#     estratégia JTIMatcher (um jti por usuário), que derruba a sessão do celular
#     ao logar no desktop. Deixar a coluna convida alguém a religar o JTIMatcher.
#   - `users.user_type_id` deixa de ser NOT NULL e perde a FK: era herança do
#     domínio de cobrança do template (user_types). `POST /auth/v1/registration`
#     não recebe `user_type_id`; com o NOT NULL, o cadastro estoura FK violation.
#
# A remoção da tabela `user_types` e do resto do domínio de cobrança NÃO é desta
# change — só relaxamos a coluna para o cadastro funcionar.
class RemoveJtiAndRelaxUserTypeOnUsers < ActiveRecord::Migration[8.0]
  def up
    remove_index  :users, name: :index_users_on_jti
    remove_column :users, :jti

    remove_foreign_key :users, column: :user_type_id
    change_column_null :users, :user_type_id, true
  end

  def down
    change_column_null :users, :user_type_id, false
    add_foreign_key :users, :user_types, column: :user_type_id

    add_column :users, :jti, :string
    add_index  :users, :jti, unique: true, name: :index_users_on_jti
  end
end
