# frozen_string_literal: true

class AddWebhookFieldsToPolemkInstances < ActiveRecord::Migration[8.0]
  def change
    add_column :polemk_instances, :connection_status, :string, default: 'unknown'
    add_column :polemk_instances, :last_connection_at, :datetime
    add_column :polemk_instances, :last_logout_at, :datetime
    add_column :polemk_instances, :logout_reason, :string
    add_column :polemk_instances, :qr_code, :text
    add_column :polemk_instances, :qr_expires_at, :datetime
    add_column :polemk_instances, :qr_session, :string
    add_column :polemk_instances, :last_qr_generated_at, :datetime
    add_column :polemk_instances, :connection_data, :json
  end
end
