# frozen_string_literal: true

class AddJtiToUsersAndCreateJwtDenylist < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :jti, :string
    add_index :users, :jti, unique: true

    create_table :jwt_denylist do |t|
      t.string :jti, null: false
      t.datetime :exp, null: false
      t.timestamps
    end
    add_index :jwt_denylist, :jti
  end
end
