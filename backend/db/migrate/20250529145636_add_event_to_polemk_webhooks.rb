# frozen_string_literal: true

class AddEventToPolemkWebhooks < ActiveRecord::Migration[8.0]
  def up
    add_column :polemk_webhooks, :event, :string
    remove_column :polemk_webhooks, :events
  end

  def down
    add_column :polemk_webhooks, :events, :string
    remove_column :polemk_webhooks, :event
  end
end
