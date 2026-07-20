# frozen_string_literal: true

class CreateClientApplications < ActiveRecord::Migration[7.2]
  def change
    create_table :client_applications do |t|
      t.string :name, null: false
      t.string :token, null: false
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_index :client_applications, :token, unique: true
  end
end
