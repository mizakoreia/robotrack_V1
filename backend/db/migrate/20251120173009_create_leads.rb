# frozen_string_literal: true

class CreateLeads < ActiveRecord::Migration[8.0]
  def change
    create_table :leads do |t|
      t.string :smart_id
      t.references :operation, null: true, foreign_key: true, index: true
      t.string :source_type, null: false
      t.string :source_id, null: false
      t.string :current_stage, default: 'discovery'
      t.datetime :last_interaction_at
      t.string :operation_key
      # Campos do lead
      t.string :name
      t.string :company_name
      t.string :session_uuid
      t.string :phone
      t.string :ig_username

      # Array JSON para armazenar todas as fontes (canais) do lead unificado
      # Permite rastrear Instagram → WhatsApp → Chat, etc.
      t.text :sources, comment: 'Array JSON com histórico de todas as fontes do lead'

      t.boolean :has_site
      t.string :site_url
      t.text :site_scrapped_text
      t.string :intention
      t.string :instruction

      # critérios do agente de encantamento
      t.string :understands_goals
      t.string :understands_smart_navigation
      t.string :understands_complexity
      t.string :understands_thats_exclusive
      t.string :understands_thats_memorable
      t.string :likes_some_site
      t.string :likes_some_app
      t.string :knows_app1_site
      t.string :knows_app2_site
      t.string :knows_app3_site
      t.string :knows_console_mod
      t.string :knows_whats_mod
      t.string :knows_own_demand

      # critérios do agente de fechamento
      t.string :validated_interest
      t.string :understands_value
      t.string :received_proposal
      t.string :gave_feedback
      t.string :ready_to_schedule

      # critérios do agente de classificação
      t.integer :discovery_level, default: 1
      t.integer :enchantment_level, default: 1
      t.integer :closing_level, default: 1

      t.integer :enchantment_criteria_count, default: 0
      t.integer :closing_criteria_count, default: 0

      t.boolean :is_categorized, default: false
      t.text :content
      t.string :content_type
      t.string :content_id
      t.string :source_endpoint, default: 'message'
      t.text :desires, array: true, default: []

      # Flag que indica se este lead foi criado através de unificação cross-channel
      # true = lead unificado de múltiplos canais, false = lead de canal único
      t.boolean :unified_from_channels, default: false, comment: 'Indica se o lead foi unificado de múltiplos canais'

      t.string :igs_id
      t.string :fb_id
      t.string :fb_username
      t.string :target_id
      t.string :execution_id

      t.timestamps
    end

    # Índices
    add_index :leads, :smart_id, unique: true
    add_index :leads, :session_uuid, unique: true
    add_index :leads, %i[source_type source_id], unique: true
    add_index :leads, :current_stage
    add_index :leads, :content_type
    add_index :leads, :source_endpoint
    add_index :leads, :target_id

    # Recriar índices sem constraint de unicidade para permitir busca eficiente
    # Índice para busca cross-channel por Instagram username (não único)
    add_index :leads, :ig_username, where: 'ig_username IS NOT NULL'

    # Índice para busca cross-channel por telefone (não único)
    add_index :leads, :phone, where: 'phone IS NOT NULL'

    # Índice para filtrar leads unificados vs leads simples
    add_index :leads, :unified_from_channels
    add_index :leads, :last_interaction_at
    add_index :leads, :igs_id, where: 'igs_id IS NOT NULL'
    add_index :leads, :fb_id, where: 'fb_id IS NOT NULL'
    add_index :leads, :fb_username, where: 'fb_username IS NOT NULL'
    # Removido: product_category foi substituído por operation_key

    # Comentários de índice (PostgreSQL)
    reversible do |dir|
      dir.up do
        execute "COMMENT ON INDEX index_leads_on_ig_username IS 'Índice para busca cross-channel por Instagram'"
        execute "COMMENT ON INDEX index_leads_on_phone IS 'Índice para busca cross-channel por telefone'"
        execute "COMMENT ON INDEX index_leads_on_unified_from_channels IS 'Índice para filtrar leads unificados'"
      end
      dir.down do
        execute 'COMMENT ON INDEX index_leads_on_ig_username IS NULL'
        execute 'COMMENT ON INDEX index_leads_on_phone IS NULL'
        execute 'COMMENT ON INDEX index_leads_on_unified_from_channels IS NULL'
      end
    end
  end
end
