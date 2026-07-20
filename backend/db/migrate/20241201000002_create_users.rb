# frozen_string_literal: true

class CreateUsers < ActiveRecord::Migration[7.1]
  def change
    create_table :users, id: :uuid do |t|
      t.string :email
      t.string :phone
      t.string :name, null: false
      t.text :avatar_url
      t.uuid :user_type_id, null: false
      t.string :provider
      t.string :provider_uid
      t.datetime :last_login_at
      t.integer :login_count, default: 0
      t.timestamps
    end

    add_index :users, :email, unique: true, where: 'email IS NOT NULL'
    add_index :users, :phone, unique: true, where: 'phone IS NOT NULL'
    add_index :users, %i[provider provider_uid], unique: true,
                                                 where: 'provider IS NOT NULL AND provider_uid IS NOT NULL'
    add_index :users, :user_type_id
    add_index :users, :last_login_at

    add_foreign_key :users, :user_types, column: :user_type_id, type: :uuid

    add_index :users, %i[email phone]
  end
end
