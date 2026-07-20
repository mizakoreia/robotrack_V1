# frozen_string_literal: true

class CreateActionTextTables < ActiveRecord::Migration[7.1]
  def change
    create_table :action_text_rich_texts, id: :uuid do |t|
      t.string     :name,     null: false
      t.references :record,   null: false, polymorphic: true, index: false, type: :uuid
      t.text       :body,     null: false
      t.datetime   :created_at, null: false
      t.datetime   :updated_at, null: false
    end

    add_index :action_text_rich_texts, %i[record_type record_id name], unique: true,
                                                                       name: 'index_action_text_rich_texts_uniqueness'
  end
end
