# frozen_string_literal: true

class CreateLoginAttempts < ActiveRecord::Migration[7.1]
  def change
    create_table :login_attempts, id: :uuid do |t|
      t.string :identifier, null: false
      t.string :method, null: false
      t.inet :ip_address, null: false
      t.text :user_agent
      t.boolean :success, null: false
      t.string :error_reason
      t.uuid :user_id
      t.timestamps
    end

    add_index :login_attempts, :identifier
    add_index :login_attempts, :ip_address
    add_index :login_attempts, :created_at
    add_index :login_attempts, :method
    add_index :login_attempts, :success
    add_index :login_attempts, %i[identifier created_at]
    add_index :login_attempts, %i[ip_address created_at]
    add_index :login_attempts, %i[identifier method created_at]
    add_index :login_attempts, %i[ip_address method created_at]
    add_index :login_attempts, %i[identifier success created_at]
    add_index :login_attempts, %i[ip_address success created_at]
    add_index :login_attempts, %i[identifier ip_address created_at], name: 'idx_login_attempts_security'

    add_foreign_key :login_attempts, :users, column: :user_id, type: :uuid
  end
end
