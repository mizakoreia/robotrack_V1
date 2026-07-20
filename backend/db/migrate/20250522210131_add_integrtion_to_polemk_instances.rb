# frozen_string_literal: true

class AddIntegrtionToPolemkInstances < ActiveRecord::Migration[8.0]
  def change
    add_column :polemk_instances, :integration, :string
    add_column :polemk_instances, :is_qrcode, :boolean
  end
end
