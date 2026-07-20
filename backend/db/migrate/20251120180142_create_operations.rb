# frozen_string_literal: true

class CreateOperations < ActiveRecord::Migration[8.0]
  def change
    create_table :operations do |t|
      t.string :key, null: false
      t.string :smart_id
      t.string :title, null: false
      t.text :description
      t.jsonb :keywords, default: []
      t.boolean :active, default: true
      t.integer :leads_count, default: 0, null: false

      t.timestamps
    end

    add_index :operations, :key, unique: true
    add_index :operations, :smart_id, unique: true
  end
end
