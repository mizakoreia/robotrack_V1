# frozen_string_literal: true

class AddLogoutInitiatorToPolemkInstances < ActiveRecord::Migration[8.0]
  def change
    add_column :polemk_instances, :logout_initiator, :string
  end
end
