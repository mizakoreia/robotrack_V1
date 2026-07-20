# frozen_string_literal: true

# Service responsável por gerenciar o sistema de Match Cross-Channel para leads
#
# LÓGICA CORRIGIDA V2:
# - Na CRIAÇÃO: API usa source_type para saber que campo comparar automaticamente
#   * Instagram (source_type) → busca leads com ig_username = source_id
#   * WhatsApp/WABA (source_type) → busca leads com phone = source_id
# - Na ATUALIZAÇÃO: Quando lead ganha phone/ig_username → pode unificar com leads existentes
#
# Fluxo de match na criação:
# 1. MATCH EXATO (source_type + source_id idênticos) - sempre prioritário
# 2. MATCH CROSS-CHANNEL INTELIGENTE - usa source_type para decidir campo de comparação
# 3. CRIAR NOVO LEAD - quando nenhum match é encontrado
class LeadCrossChannelService
  # Método principal para buscar ou criar lead (usado na criação)
  def self.find_or_create_lead(attributes)
    new(attributes).find_or_create_lead
  end

  # Método para verificar unificação durante atualização de lead existente
  def self.check_unification_on_update(lead, new_attributes)
    new(new_attributes).check_unification_for_existing_lead(lead)
  end

  def initialize(attributes)
    @attributes = attributes.with_indifferent_access
    @source_type = @attributes[:source_type]
    @source_id = @attributes[:source_id]
  end

  # Executa a lógica de busca/criação (usado principalmente na criação de leads)
  def find_or_create_lead
    # 1. MATCH EXATO - prioridade máxima (source_type + source_id idênticos)
    exact_match = find_exact_match
    return update_existing_lead(exact_match) if exact_match

    # 2. MATCH CROSS-CHANNEL INTELIGENTE - usa source_type para decidir comparação
    # Agora NA CRIAÇÃO também verifica cross-channel baseado no source_type
    cross_channel_match = find_intelligent_cross_channel_match
    return unify_with_existing_lead(cross_channel_match) if cross_channel_match

    # 3. CRIAR NOVO LEAD - quando nenhum match é encontrado
    create_new_lead
  end

  # Verifica se um lead existente deve ser unificado após atualização
  # Este método é chamado quando um lead ganha novos dados (phone, ig_username)
  def check_unification_for_existing_lead(current_lead)
    return current_lead unless has_cross_channel_data_for_update?

    # Busca leads que podem ser unificados baseado nos novos dados
    potential_match = find_cross_channel_match_excluding(current_lead)

    if potential_match
      # CORRIGIDO: Unifica mantendo o lead ATUAL como principal (não o mais antigo)
      unify_leads_keeping_current(current_lead, potential_match)
    else
      current_lead
    end
  end

  private

  # Busca lead com source_type + source_id exatamente iguais
  def find_exact_match
    Lead.find_by(source_type: @source_type, source_id: @source_id)
  end

  # NOVO: Match cross-channel inteligente baseado no source_type (para criação)
  # Usa o source_type para saber que campo comparar nos leads existentes
  def find_intelligent_cross_channel_match
    case @source_type.to_s.downcase
    when 'instagram'
      # Instagram: source_id deve ser comparado com ig_username de leads existentes
      find_lead_by_ig_username(@source_id)
    when 'waba', 'whatsapp'
      # WhatsApp: source_id deve ser comparado com phone de leads existentes
      # Assumindo que source_id é o telefone (padrão WhatsApp Business API)
      find_lead_by_phone(@source_id)
    end
  end

  # Verifica se temos dados suficientes para match cross-channel (para atualizações)
  def has_cross_channel_data?
    case @source_type.to_s.downcase
    when 'instagram'
      @attributes[:ig_username].present?
    when 'waba', 'whatsapp'
      # Para WhatsApp, o source_id geralmente É o telefone
      # Mas também pode vir um campo phone separado
      phone_from_source_id || @attributes[:phone].present?
    else
      false
    end
  end

  # Extrai telefone do source_id quando é WhatsApp/WABA
  def phone_from_source_id
    return nil unless %w[waba whatsapp].include?(@source_type.to_s.downcase)

    # Source_id do WhatsApp geralmente é o número de telefone
    # Exemplo: "5511999999999" ou "+5511999999999"
    @source_id if @source_id.to_s.match?(/^\+?\d{10,15}$/)
  end

  # Busca lead de canal diferente mas mesmo usuário (cross-channel) - para atualizações
  def find_cross_channel_match
    case @source_type.to_s.downcase
    when 'instagram'
      find_by_instagram_username
    when 'waba', 'whatsapp'
      find_by_phone
    end
  end

  # Busca lead cross-channel excluindo o lead atual (para unificação)
  def find_cross_channel_match_excluding(current_lead)
    # CORRIGIDO: Para atualizações, deve buscar baseado nos novos dados que estão chegando
    ig_username = @attributes[:ig_username]
    phone = @attributes[:phone]

    if ig_username.present?
      Lead.where.not(ig_username: nil)
          .where.not(id: current_lead.id)
          .where(ig_username: ig_username)
          .first
    elsif phone.present?
      Lead.where.not(phone: nil)
          .where.not(id: current_lead.id)
          .where(phone: phone)
          .first
    end
  end

  # NOVOS MÉTODOS: Busca direta por campo específico (para match inteligente na criação)

  # Busca lead que tenha ig_username igual ao valor fornecido
  def find_lead_by_ig_username(username)
    return nil if username.blank?

    Lead.where.not(ig_username: nil)
        .where(ig_username: username)
        .first
  end

  # Busca lead que tenha phone igual ao valor fornecido
  def find_lead_by_phone(phone)
    return nil if phone.blank?

    Lead.where.not(phone: nil)
        .where(phone: phone)
        .first
  end

  # MÉTODOS EXISTENTES: Busca por dados nos atributos (para atualizações)

  # Busca lead existente que tenha o mesmo Instagram username
  def find_by_instagram_username
    return nil if @attributes[:ig_username].blank?

    Lead.where.not(ig_username: nil)
        .where(ig_username: @attributes[:ig_username])
        .first
  end

  # Busca lead existente que tenha o mesmo Instagram username (excluindo lead atual)
  def find_by_instagram_username_excluding(current_lead)
    return nil if @attributes[:ig_username].blank?

    Lead.where.not(ig_username: nil)
        .where.not(id: current_lead.id)
        .where(ig_username: @attributes[:ig_username])
        .first
  end

  # Busca lead existente que tenha o mesmo telefone
  def find_by_phone
    phone = @attributes[:phone] || phone_from_source_id
    return nil if phone.blank?

    Lead.where.not(phone: nil)
        .where(phone: phone)
        .first
  end

  # Busca lead existente que tenha o mesmo telefone (excluindo lead atual)
  def find_by_phone_excluding(current_lead)
    phone = @attributes[:phone] || phone_from_source_id
    return nil if phone.blank?

    Lead.where.not(phone: nil)
        .where.not(id: current_lead.id)
        .where(phone: phone)
        .first
  end

  # Atualiza lead existente com dados de nova interação (match exato)
  def update_existing_lead(lead)
    update_attrs = extract_mergeable_attributes
    update_attrs[:last_interaction_at] = Time.current

    lead.update!(update_attrs) if update_attrs.any?
    lead
  end

  # Unifica novo canal com lead existente de canal diferente (cross-channel)
  def unify_with_existing_lead(lead)
    add_source_to_lead(lead, @source_type, @source_id)

    # Mescla novos dados sem sobrescrever campos importantes
    update_attributes = extract_mergeable_attributes.merge(
      last_interaction_at: Time.current
    )

    # IMPORTANTE: Para match inteligente, precisamos garantir que o campo correto seja preenchido
    update_attributes.merge!(ensure_cross_channel_field_populated)

    lead.update!(update_attributes) if update_attributes.any?
    lead
  end

  # NOVO: Garante que o campo cross-channel correto seja preenchido após unificação
  def ensure_cross_channel_field_populated
    case @source_type.to_s.downcase
    when 'instagram'
      # Se veio do Instagram, preenche ig_username se não estiver preenchido
      { ig_username: @source_id }
    when 'waba', 'whatsapp'
      # Se veio do WhatsApp, preenche phone se não estiver preenchido
      { phone: @source_id }
    else
      {}
    end
  end

  # Unifica dois leads existentes (mantém o mais antigo)
  def unify_leads(main_lead, secondary_lead)
    # Transfere todas as fontes do lead secundário para o principal
    secondary_sources = secondary_lead.all_sources

    secondary_sources.each do |source|
      add_source_to_lead(main_lead, source[:source_type], source[:source_id])
    end

    # Transfere mensagens do lead secundário para o principal
    secondary_lead.messages.update_all(lead_id: main_lead.id)

    # Mescla dados do lead secundário no principal (sem sobrescrever)
    secondary_data = extract_mergeable_attributes_from_lead(secondary_lead)
    main_lead.update!(secondary_data.merge(last_interaction_at: Time.current)) if secondary_data.any?

    # Remove o lead secundário após unificação
    secondary_lead.destroy!

    main_lead
  end

  # NOVO: Unifica dois leads mantendo o lead atual como principal
  def unify_leads_keeping_current(current_lead, secondary_lead)
    Rails.logger.info "🔄 Unificando leads: mantendo #{current_lead.smart_id} (atual), removendo #{secondary_lead.smart_id}"

    # Transfere todas as fontes do lead secundário para o atual
    secondary_sources = secondary_lead.all_sources

    secondary_sources.each do |source|
      add_source_to_lead(current_lead, source[:source_type], source[:source_id])
    end

    # Transfere mensagens do lead secundário para o atual
    message_count = secondary_lead.messages.count
    secondary_lead.messages.update_all(lead_id: current_lead.id)
    Rails.logger.info "📨 Transferidas #{message_count} mensagens"

    # Mescla dados do lead secundário no atual (sem sobrescrever)
    secondary_data = extract_mergeable_attributes_from_lead(secondary_lead)

    # IMPORTANTE: Aplica os novos dados da atualização PRIMEIRO
    update_data = extract_mergeable_attributes

    # Mescla: dados do secondary + dados da atualização (atualização tem prioridade)
    merged_data = secondary_data.merge(update_data).merge(last_interaction_at: Time.current)

    # CORRIGIDO: Aplica os dados mesclados ao lead atual
    current_lead.update!(merged_data) if merged_data.any?
    Rails.logger.info "💾 Dados mesclados no lead principal: #{merged_data.keys.join(', ')}"

    # Remove o lead secundário após unificação
    Rails.logger.info "🗑️ Removendo lead secundário #{secondary_lead.smart_id}"
    secondary_lead.destroy!

    # IMPORTANTE: Recarrega o lead para garantir que todas as mudanças foram aplicadas
    current_lead.reload
  end

  # Cria novo lead quando nenhum match foi encontrado
  def create_new_lead
    # NOVO: Para criação inteligente, popula automaticamente o campo correto
    create_attributes = @attributes.merge(auto_populate_cross_channel_field)

    lead = Lead.create!(create_attributes)

    # Inicializa array de fontes para o novo lead
    source_data = [build_source_entry(@source_type, @source_id, lead.created_at)]
    lead.update!(sources: source_data.to_json)

    lead
  end

  # NOVO: Popula automaticamente o campo cross-channel correto na criação
  def auto_populate_cross_channel_field
    case @source_type.to_s.downcase
    when 'instagram'
      # Instagram: source_id vira ig_username automaticamente
      { ig_username: @source_id }
    when 'waba', 'whatsapp'
      # WhatsApp: source_id vira phone automaticamente (se for telefone válido)
      phone_value = phone_from_source_id || @source_id
      { phone: phone_value }
    else
      {}
    end
  end

  # Adiciona uma nova fonte a um lead existente
  def add_source_to_lead(lead, source_type, source_id)
    current_sources = lead.sources.present? ? JSON.parse(lead.sources) : []

    # Adiciona fonte original se array estiver vazio
    current_sources << build_source_entry(lead.source_type, lead.source_id, lead.created_at) if current_sources.empty?

    # Adiciona nova fonte se ainda não existe
    unless source_already_exists?(current_sources, source_type, source_id)
      current_sources << build_source_entry(source_type, source_id, Time.current)
    end

    lead.update!(
      sources: current_sources.to_json,
      unified_from_channels: true
    )
  end

  # Constrói entrada para array de fontes
  def build_source_entry(source_type, source_id, timestamp)
    {
      source_type: source_type,
      source_id: source_id,
      added_at: timestamp
    }
  end

  # Verifica se a fonte já existe no array
  def source_already_exists?(sources, source_type, source_id)
    sources.any? do |source|
      source['source_type'] == source_type && source['source_id'] == source_id
    end
  end

  # Extrai campos que podem ser mesclados dos atributos
  def extract_mergeable_attributes
    mergeable = {}

    # Campos que podem ser preenchidos apenas se estiverem vazios no lead de destino
    %i[name company_name phone ig_username intention instruction].each do |field|
      mergeable[field] = @attributes[field] if @attributes[field].present?
    end

    # Campos que sempre podem ser atualizados
    %i[content content_type content_id source_endpoint].each do |field|
      mergeable[field] = @attributes[field] if @attributes[field].present?
    end

    mergeable
  end

  # Extrai campos mergeáveis de um lead existente (para unificação de leads)
  def extract_mergeable_attributes_from_lead(source_lead)
    mergeable = {}

    %i[name company_name phone ig_username intention instruction content content_type content_id
       source_endpoint].each do |field|
      value = source_lead.send(field)
      mergeable[field] = value if value.present?
    end

    mergeable
  end

  # NOVO: Verifica dados cross-channel especificamente para atualizações
  def has_cross_channel_data_for_update?
    # Para atualizações, verifica se temos dados nos atributos que estão sendo atualizados
    @attributes[:ig_username].present? || @attributes[:phone].present?
  end
end
