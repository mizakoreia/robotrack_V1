# frozen_string_literal: true

class CreatePolemkWebhooks < ActiveRecord::Migration[8.0]
  def change
    create_table :polemk_webhooks do |t|
      t.integer :polemk_instance_id
      t.string :url
      t.boolean :enabled, default: true
      t.boolean :webhook_by_events, default: true
      t.boolean :webhook_base_64, default: true
      t.json :events
      t.json :raw_response

      t.timestamps
    end
  end
end
