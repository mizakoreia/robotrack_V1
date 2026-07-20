# frozen_string_literal: true

class CreatePermissions < ActiveRecord::Migration[8.0]
  def change
    create_table :permissions do |t|
      t.string :key, null: false
      t.string :title, null: false
      t.text :description
      t.boolean :is_active, default: true, null: false
      t.integer :sort_order, default: 0
      t.timestamps
    end

    add_index :permissions, :key, unique: true
    add_index :permissions, :is_active
    add_index :permissions, :sort_order

    create_table :plan_feature_permissions do |t|
      t.references :plan_feature, null: false, foreign_key: true
      t.references :permission, null: false, foreign_key: true
      t.timestamps
    end
    add_index :plan_feature_permissions, %i[plan_feature_id permission_id], unique: true, name: 'idx_pf_perm_unique'

    create_table :user_permissions do |t|
      t.references :user, null: false, type: :uuid, foreign_key: { to_table: :users }
      t.references :permission, null: false, foreign_key: true
      t.string :source, null: false # plan | feature | manual
      t.bigint :source_id
      t.datetime :granted_at, null: false
      t.datetime :revoked_at
      t.timestamps
    end
    add_index :user_permissions, %i[user_id permission_id revoked_at], name: 'idx_user_perm_active'
    add_index :user_permissions, %i[user_id permission_id source source_id], unique: true,
                                                                             name: 'idx_user_perm_source_unique'

    create_table :permission_conflicts do |t|
      t.references :permission, null: false, foreign_key: true
      t.references :conflicts_with, null: false, foreign_key: { to_table: :permissions }
      t.timestamps
    end
    add_index :permission_conflicts, %i[permission_id conflicts_with_id], unique: true,
                                                                          name: 'idx_perm_conflict_unique'

    create_table :permission_audit_logs do |t|
      t.references :user, null: false, type: :uuid, foreign_key: { to_table: :users }
      t.references :plan, foreign_key: true
      t.string :change_type, null: false # grant | revoke | sync
      t.jsonb :permissions_added, default: []
      t.jsonb :permissions_removed, default: []
      t.string :source_event
      t.string :reason
      t.references :actor, polymorphic: true, type: :uuid
      t.jsonb :metadata, default: {}
      t.timestamps
    end
    add_index :permission_audit_logs, :change_type
    add_index :permission_audit_logs, :source_event
  end
end
