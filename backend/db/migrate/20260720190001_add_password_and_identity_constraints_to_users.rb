# frozen_string_literal: true

# identity-and-auth 1.2 — migration ADITIVA (não destrutiva).
#
# Materializa o piso de identidade no banco:
#   - `encrypted_password` (convenção Devise database_authenticatable);
#   - `email` NOT NULL com índice único TOTAL (o RoboTrack não tem login por
#     telefone; e-mail é a chave de identidade — D4.5);
#   - CHECK de nome não-vazio (D4.6): `author_name_snapshot`, notificações e
#     auditoria nunca podem renderizar um nome em branco no meio de uma frase;
#   - CHECK de credencial (D4.7): quem não tem `provider` precisa de senha, senão
#     existiria um usuário que nunca conseguiria entrar;
#   - `jwt_denylist.jti` passa de índice comum a ÚNICO (D4.1): duas revogações
#     concorrentes do mesmo `jti` não podem gravar duas linhas.
#
# As invariantes moram no BANCO, não só no model: `update_column`/`insert` cru
# pelo console têm de esbarrar nelas.
class AddPasswordAndIdentityConstraintsToUsers < ActiveRecord::Migration[8.0]
  def up
    add_column :users, :encrypted_password, :string, null: false, default: ''

    # E-mail é a chave. Deixa de ser opcional; o índice único parcial
    # (WHERE email IS NOT NULL) dá lugar a um índice único total.
    change_column_null :users, :email, false
    remove_index :users, name: :index_users_on_email
    add_index :users, :email, unique: true, name: :index_users_on_email

    # Nome de exibição sempre presente e não-vazio (D4.6).
    add_check_constraint :users,
                         "char_length(btrim(name)) >= 2",
                         name: 'users_name_min_length'

    # Credencial mínima (D4.7): provider OU senha, nunca nenhum dos dois.
    add_check_constraint :users,
                         "provider IS NOT NULL OR encrypted_password <> ''",
                         name: 'users_credential_present'

    # Revogação por Denylist exige unicidade do jti (D4.1).
    remove_index :jwt_denylist, name: :index_jwt_denylist_on_jti
    add_index :jwt_denylist, :jti, unique: true, name: :index_jwt_denylist_on_jti
  end

  def down
    remove_index :jwt_denylist, name: :index_jwt_denylist_on_jti
    add_index :jwt_denylist, :jti, name: :index_jwt_denylist_on_jti

    remove_check_constraint :users, name: 'users_credential_present'
    remove_check_constraint :users, name: 'users_name_min_length'

    remove_index :users, name: :index_users_on_email
    add_index :users, :email, unique: true, name: :index_users_on_email,
                              where: 'email IS NOT NULL'
    change_column_null :users, :email, true

    remove_column :users, :encrypted_password
  end
end
