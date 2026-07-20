# frozen_string_literal: true

class CreateLoginCodes < ActiveRecord::Migration[7.1]
  def change
    create_table :login_codes, id: :uuid do |t|
      t.uuid :user_id
      t.string :destination, null: false
      t.string :code, null: false
      t.string :method, null: false
      t.datetime :expires_at, null: false
      t.datetime :used_at
      t.integer :attempts, default: 0
      t.timestamps
    end

    add_index :login_codes, :destination
    add_index :login_codes, :code
    add_index :login_codes, :expires_at
    add_index :login_codes, :used_at
    add_index :login_codes, :user_id
    add_index :login_codes, :method
    add_index :login_codes, %i[destination method]
    add_index :login_codes, %i[destination method expires_at], name: 'idx_login_codes_dest_method_expires',
                                                               where: 'used_at IS NULL'
    add_index :login_codes, :created_at

    add_foreign_key :login_codes, :users, column: :user_id, type: :uuid
  end
end
