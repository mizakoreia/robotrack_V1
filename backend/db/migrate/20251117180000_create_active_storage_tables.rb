# frozen_string_literal: true

class CreateActiveStorageTables < ActiveRecord::Migration[7.1]
  def change
    unless table_exists?(:active_storage_blobs)
      create_table :active_storage_blobs, id: :uuid do |t|
        t.string   :key,          null: false
        t.string   :filename,     null: false
        t.string   :content_type
        t.text     :metadata
        t.bigint   :byte_size,    null: false
        t.string   :checksum,     null: false
        t.datetime :created_at,   null: false
      end
      add_index :active_storage_blobs, :key, unique: true unless index_exists?(:active_storage_blobs, :key)
    end

    unless table_exists?(:active_storage_attachments)
      create_table :active_storage_attachments, id: :uuid do |t|
        t.string     :name,     null: false
        t.references :record,   null: false, polymorphic: true, index: false, type: :uuid
        t.references :blob,     null: false, type: :uuid
        t.datetime   :created_at, null: false
      end
      unless index_exists?(:active_storage_attachments, %i[record_type record_id name blob_id],
                           name: 'index_active_storage_attachments_uniqueness')
        add_index :active_storage_attachments, %i[record_type record_id name blob_id], unique: true,
                                                                                       name: 'index_active_storage_attachments_uniqueness'
      end
    end

    return if table_exists?(:active_storage_variant_records)

    create_table :active_storage_variant_records, id: :uuid do |t|
      t.references :blob, null: false, type: :uuid
      t.string     :variation_digest, null: false
    end
    unless index_exists?(:active_storage_variant_records, %i[blob_id variation_digest],
                         name: 'index_active_storage_variants_uniqueness')
      add_index :active_storage_variant_records, %i[blob_id variation_digest], unique: true,
                                                                               name: 'index_active_storage_variants_uniqueness'
    end
  end
end
