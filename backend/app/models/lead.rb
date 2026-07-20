# frozen_string_literal: true

class Lead < ApplicationRecord
  has_many :messages, class_name: 'LeadMessage', foreign_key: 'lead_id', dependent: :destroy
  belongs_to :operation, class_name: 'Operation', foreign_key: 'operation_id', optional: true

  validates :session_uuid, presence: true, uniqueness: true
  validates :smart_id, uniqueness: true, allow_blank: true
  validates :source_type, presence: true
  validates :source_id, presence: true
  validates :current_stage, inclusion: { in: %w[discovery enchantment closing] }
  validates :discovery_level, inclusion: { in: 1..5 }
  validates :enchantment_level, inclusion: { in: 1..5 }
  validates :closing_level, inclusion: { in: 1..5 }
  validate :validate_desires_format
  validates :source_endpoint, inclusion: { in: %w[message comment reaction call] }, allow_nil: false, if: lambda {
    has_attribute?(:source_endpoint)
  }

  before_validation :generate_session_uuid, on: :create
  before_validation :normalize_criteria_fields
  before_validation :set_social_ids_from_source, on: :create
  before_validation :set_operation_from_key
  before_validation :set_default_source_endpoint, on: :create
  before_create :generate_smart_id

  before_save :update_categorization_status, if: -> { will_save_change_to_attribute?(:operation_id) }

  after_update :update_operation_leads_count_on_change, if: -> { saved_change_to_attribute?(:operation_id) }
  after_destroy :update_operation_leads_count_on_destroy

  scope :by_source, ->(source_type, source_id) { where(source_type: source_type, source_id: source_id) }
  scope :by_target, ->(target_id) { where(target_id: target_id) }
  scope :by_stage, ->(stage) { where(current_stage: stage) }
  scope :by_level, ->(stage, level) { where("#{stage}_level" => level) }
  scope :by_session_uuid, ->(session_uuid) { where(session_uuid: session_uuid) }
  scope :by_smart_id, ->(smart_id) { where(smart_id: smart_id) }

  scope :by_operation, ->(operation_id) { where(operation_id: operation_id) }
  scope :by_operation_key, ->(operation_key) { where(operation_key: operation_key) }
  scope :categorized, -> { where(is_categorized: true) }
  scope :uncategorized, -> { where(is_categorized: false) }
  scope :with_operation, -> { where.not(operation_id: nil) }
  scope :without_operation, -> { where(operation_id: nil) }

  scope :with_desires, -> { where('array_length(desires, 1) > 0') }
  scope :without_desires, -> { where('desires IS NULL OR array_length(desires, 1) = 0') }
  scope :by_source_endpoint, ->(endpoint) { where(source_endpoint: endpoint) }
  scope :messages_only, -> { where(source_endpoint: 'message') }
  scope :comments_only, -> { where(source_endpoint: 'comment') }
  scope :reactions_only, -> { where(source_endpoint: 'reaction') }
  scope :calls_only, -> { where(source_endpoint: 'call') }
  scope :by_content_type, ->(type) { where(content_type: type) }
  scope :with_text_content, -> { where(content_type: 'text') }
  scope :with_audio_content, -> { where(content_type: 'audio') }
  scope :with_video_content, -> { where(content_type: 'video') }
  scope :with_ephemeral_content, -> { where(content_type: 'ephemeral') }
  scope :by_igs_id, ->(igs_id) { where(igs_id: igs_id) }
  scope :by_fb_id, ->(fb_id) { where(fb_id: fb_id) }
  scope :by_fb_username, ->(fb_username) { where(fb_username: fb_username) }
  scope :by_target_id, ->(target_id) { where(target_id: target_id) }

  scope :that_understands_goals, -> { where.not(understands_goals: nil) }
  scope :that_understands_smart_navigation, -> { where.not(understands_smart_navigation: nil) }
  scope :that_understands_complexity, -> { where.not(understands_complexity: nil) }
  scope :that_understands_thats_exclusive, -> { where.not(understands_thats_exclusive: nil) }
  scope :that_understands_thats_memorable, -> { where.not(understands_thats_memorable: nil) }
  scope :that_likes_some_site, -> { where.not(likes_some_site: nil) }
  scope :that_likes_some_app, -> { where.not(likes_some_app: nil) }
  scope :that_knows_app1_site, -> { where.not(knows_app1_site: nil) }
  scope :that_knows_app2_site, -> { where.not(knows_app2_site: nil) }
  scope :that_knows_app3_site, -> { where.not(knows_app3_site: nil) }
  scope :that_knows_console_mod, -> { where.not(knows_console_mod: nil) }
  scope :that_knows_whats_mod, -> { where.not(knows_whats_mod: nil) }
  scope :that_knows_own_demand, -> { where.not(knows_own_demand: nil) }

  scope :that_validated_interest, -> { where.not(validated_interest: nil) }
  scope :that_understands_value, -> { where.not(understands_value: nil) }
  scope :that_received_proposal, -> { where.not(received_proposal: nil) }
  scope :that_gave_feedback, -> { where.not(gave_feedback: nil) }
  scope :that_ready_to_schedule, -> { where.not(ready_to_schedule: nil) }

  ENCHANTMENT_CRITERIA = {
    'understands_goals' => 'O cliente entendeu que nosso objetivo é criar sites únicos e memoráveis no nicho dele?',
    'understands_smart_navigation' => 'O cliente compreendeu o conceito de navegação inteligente e estrutura diferenciada?',
    'understands_complexity' => 'O cliente entendeu a diferença de complexidade entre nossas soluções personalizadas e genéricas como WordPress?',
    'understands_thats_exclusive' => 'O cliente compreendeu que terá um site exclusivo para sua empresa, não adaptado de template?',
    'understands_thats_memorable' => 'O cliente concordou que sites personalizados são mais memoráveis que soluções genéricas?',
    'likes_some_site' => 'O cliente demonstrou gostar de algum site do nosso portfólio?',
    'likes_some_app' => 'O cliente demonstrou interesse em alguma funcionalidade ou app que apresentamos?',
    'knows_app1_site' => 'O cliente foi apresentado a um site de referência (app1)?',
    'knows_app2_site' => 'O cliente foi apresentado a um segundo site de referência (app2)?',
    'knows_app3_site' => 'O cliente foi apresentado a um terceiro site de referência (app3)?',
    'knows_console_mod' => 'O cliente entendeu que terá um painel administrativo para gerenciar todo o conteúdo?',
    'knows_whats_mod' => 'O cliente foi apresentado à integração WhatsApp e suas possibilidades futuras?',
    'knows_own_demand' => 'Identificamos e registramos claramente a demanda específica do cliente para o projeto?'
  }.freeze

  CLOSING_CRITERIA = {
    'validated_interest' => 'O cliente demonstrou interesse claro no projeto antes da reunião?',
    'understands_value' => 'O cliente compreendeu o valor da proposta e o que está incluído nos serviços?',
    'received_proposal' => 'O cliente recebeu e acessou o link do orçamento/proposta comercial?',
    'gave_feedback' => 'O cliente forneceu feedback sobre a proposta apresentada?',
    'ready_to_schedule' => 'O cliente demonstrou intenção de avançar e agendar próximos passos?'
  }.freeze

  ENCHANTMENT_CRITERIA_FIELDS = %w[
    understands_goals
    understands_smart_navigation
    understands_complexity
    understands_thats_exclusive
    understands_thats_memorable
    likes_some_site
    likes_some_app
    knows_app1_site
    knows_app2_site
    knows_app3_site
    knows_console_mod
    knows_whats_mod
    knows_own_demand
  ].freeze

  CLOSING_CRITERIA_FIELDS = %w[
    validated_interest
    understands_value
    received_proposal
    gave_feedback
    ready_to_schedule
  ].freeze

  ALL_CRITERIA_FIELDS = (ENCHANTMENT_CRITERIA_FIELDS + CLOSING_CRITERIA_FIELDS).freeze

  def self.enchantment_question(field_name)
    ENCHANTMENT_CRITERIA[field_name.to_s]
  end

  def self.closing_question(field_name)
    CLOSING_CRITERIA[field_name.to_s]
  end

  def self.all_enchantment_criteria
    ENCHANTMENT_CRITERIA
  end

  def self.all_closing_criteria
    CLOSING_CRITERIA
  end

  def self.all_criteria
    ENCHANTMENT_CRITERIA.merge(CLOSING_CRITERIA)
  end

  def self.by_any_id(any_id)
    return nil if any_id.blank?

    any_id_str = any_id.to_s.strip

    return find_by(smart_id: any_id_str.upcase) if any_id_str.match?(/\ALD-[A-Z0-9]{10}\z/i)

    return find_by(id: any_id_str.to_i) if any_id_str.match?(/\A\d+\z/)

    find_by(session_uuid: any_id_str)
  end

  def update_last_interaction!
    update!(last_interaction_at: Time.current)
  end

  def update_last_interaction_with_content!(message_content = nil, message_type = nil, message_id = nil)
    attrs = { last_interaction_at: Time.current }
    if message_content.present?
      attrs[:content] = message_content
      attrs[:content_type] = message_type.presence || 'text'
      attrs[:content_id] = message_id if message_id.present?
    end
    update!(attrs)
  end

  def advance_level(stage)
    current_level = send("#{stage}_level")
    return unless current_level < 5

    update!("#{stage}_level" => current_level + 1)
  end

  def progress_summary
    {
      discovery: discovery_level,
      enchantment: enchantment_level,
      closing: closing_level,
      total: discovery_level + enchantment_level + closing_level
    }
  end

  def enchantment_criteria_completed_count
    ENCHANTMENT_CRITERIA_FIELDS.count { |field| send(field).present? }
  end

  def closing_criteria_completed_count
    CLOSING_CRITERIA_FIELDS.count { |field| send(field).present? }
  end

  def total_criteria_completed_count
    enchantment_criteria_completed_count + closing_criteria_completed_count
  end

  before_save :update_criteria_counts

  def associate_with_operation(operation_id)
    operation = Operation.find(operation_id)
    return false unless operation

    self.operation_id = operation.id
    self.operation_key = operation.key
    self.is_categorized = true
    save
  end

  def associate_with_operation_by_key(operation_key)
    operation = Operation.find_by(key: operation_key)
    return false unless operation

    self.operation_id = operation.id
    self.operation_key = operation.key
    self.is_categorized = true
    save
  end

  def dissociate_from_operation
    self.operation_id = nil
    self.operation_key = nil
    self.is_categorized = false
    save
  end

  def associated_operation
    operation
  end

  def has_operation?
    respond_to?(:operation_id) && operation_id.present?
  end

  def all_sources
    return [{ source_type: source_type, source_id: source_id }] if sources.blank?

    JSON.parse(sources).map(&:with_indifferent_access)
  end

  def cross_channel_unified?
    unified_from_channels == true
  end

  def sources_description
    all_sources.map { |s| "#{s[:source_type]}:#{s[:source_id]}" }.join(', ')
  end

  private

  def generate_session_uuid
    if source_type.to_s.downcase == 'chat' && source_id.present?
      self.session_uuid = source_id
    else
      self.session_uuid ||= SecureRandom.uuid
    end
  end

  def normalize_criteria_fields
    ALL_CRITERIA_FIELDS.each do |field|
      value = send(field)
      send("#{field}=", nil) if value.is_a?(String) && value.strip.empty?
    end
  end

  def set_social_ids_from_source
    case source_type.to_s.downcase
    when 'instagram'
      self.igs_id ||= source_id if source_id.present? && has_attribute?(:igs_id)
    when 'facebook'
      self.fb_id ||= source_id if source_id.present? && has_attribute?(:fb_id)
    when 'chat'
      if source_id.present? && has_attribute?(:session_uuid) && session_uuid.blank?
        self.session_uuid = source_id
      elsif has_attribute?(:session_uuid) && session_uuid.present? && source_id.blank?
        self.source_id = session_uuid
      end
    end
  end

  def set_default_source_endpoint
    return unless has_attribute?(:source_endpoint)

    self.source_endpoint ||= 'message'
  end

  def set_operation_from_key
    if operation_key.present?
      op = Operation.find_by(key: operation_key)
      if op
        self.operation_id = op.id
        self.is_categorized = true
      else
        self.operation_id = nil
      end
    elsif operation_id.present? && operation_key.blank?
      op = Operation.find_by(id: operation_id)
      self.operation_key = op&.key
    end
  end

  def generate_smart_id
    return if smart_id.present?

    loop do
      rid = "LD-#{SecureRandom.alphanumeric(10).upcase}"
      unless Lead.exists?(smart_id: rid)
        self.smart_id = rid
        break
      end
    end
  end

  def update_criteria_counts
    self.enchantment_criteria_count = enchantment_criteria_completed_count
    self.closing_criteria_count = closing_criteria_completed_count
  end

  def update_categorization_status
    if operation_id.present?
      self.is_categorized = true
      if operation_key.blank? && operation_id.present?
        operation = Operation.find_by(id: operation_id)
        self.operation_key = operation&.key
      end
    else
      self.is_categorized = false
      self.operation_key = nil
    end
  end

  def update_operation_leads_count_on_change
    prev_op_id = attribute_before_last_save(:operation_id)
    if prev_op_id.present?
      old_operation = Operation.find_by(id: prev_op_id)
      old_operation&.update_leads_count!
    end

    return unless operation_id.present?

    operation&.update_leads_count!
  end

  def update_operation_leads_count_on_destroy
    operation&.update_leads_count!
  end

  def validate_desires_format
    return if desires.nil?

    return if desires.is_a?(Array) && desires.all? { |desire| desire.is_a?(String) }

    errors.add(:desires, 'deve ser um array de strings')
  end
end
