# frozen_string_literal: true

class CreatePolemkInstances < ActiveRecord::Migration[8.0]
  def change
    create_table :polemk_instances do |t|
      t.string :display_name
      t.string :instance_name
      t.string :instance_id
      t.string :api_key
      t.string :number
      t.json   :raw_response

      t.timestamps
    end
  end
end
