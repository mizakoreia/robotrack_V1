# frozen_string_literal: true

class CreatePolemkInstanceGroups < ActiveRecord::Migration[8.0]
  def change
    create_table :polemk_instance_groups do |t|
      t.string :group_id
      t.string :group_name
      t.integer :polemk_instance_id
      t.json :raw_response
      t.timestamps
    end
  end
end
