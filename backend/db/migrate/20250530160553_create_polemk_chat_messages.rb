# frozen_string_literal: true

class CreatePolemkChatMessages < ActiveRecord::Migration[8.0]
  def change
    create_table :polemk_chat_messages do |t|
      t.integer :polemk_instance_id
      t.integer :polemk_instance_group_id
      t.string :full_number, null: false
      t.text :message, null: false
      t.string :ip_address
      t.string :user_agent

      t.timestamps
    end

    add_index :polemk_chat_messages, :ip_address
    add_index :polemk_chat_messages, :full_number
  end
end
