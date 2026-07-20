# frozen_string_literal: true

class LeadMessage < ApplicationRecord
  CONTENT_TYPES = %w[text image audio video file document].freeze
  MEDIA_TYPES = CONTENT_TYPES - ['text']

  belongs_to :lead, class_name: 'Lead', foreign_key: 'lead_id'
  belongs_to :user, class_name: 'User', foreign_key: 'user_id', optional: true

  validates :lead_id, presence: true
  validates :smart_id, uniqueness: true, allow_blank: true
  validates :sender_role, presence: true, inclusion: { in: %w[user agent admin] }
  validates :content, presence: true
  validates :group_id, presence: true
  validates :content_type, inclusion: { in: CONTENT_TYPES }

  validates :media_url, presence: true, if: :media?
  validates :media_mime, presence: true, if: :media?

  before_validation :generate_group_id, on: :create, unless: :group_id?
  before_validation :set_default_content_type

  scope :by_sender, ->(role) { where(sender_role: role) }
  scope :by_group, ->(group_id) { where(group_id: group_id) }
  scope :by_agent_type, ->(agent_type) { where(agent_type: agent_type) }
  scope :by_instruction, ->(instruction) { where('instruction ILIKE ?', "%#{instruction}%") }
  scope :user_messages, -> { where(sender_role: 'user') }
  scope :agent_messages, -> { where(sender_role: 'agent') }
  scope :recent, -> { order(created_at: :desc) }
  scope :by_content_type, ->(type) { where(content_type: type) }
  scope :text_messages, -> { where(content_type: 'text') }
  scope :media_messages, -> { where.not(content_type: 'text') }
  scope :images, -> { where(content_type: 'image') }
  scope :audios, -> { where(content_type: 'audio') }
  scope :videos, -> { where(content_type: 'video') }
  scope :files, -> { where(content_type: 'file') }

  after_create :update_lead_interaction
  after_create :update_lead_last_message

  def self.create_bulk(messages_data, custom_group_id: nil)
    group_id = custom_group_id || generate_bulk_group_id

    transaction do
      messages_data.map do |message_data|
        create!(message_data.merge(group_id: group_id))
      end
    end
  end

  def self.by_any_id(any_id)
    return nil if any_id.blank?

    any_id_str = any_id.to_s.strip

    return find_by(smart_id: any_id_str.upcase) if any_id_str.match?(/\AMSG-[A-Z0-9]{10}\z/i)

    return find_by(id: any_id_str.to_i) if any_id_str.match?(/\A\d+\z/)

    nil
  end

  def media?
    MEDIA_TYPES.include?(content_type)
  end

  def media_url_with_fallback
    return nil unless media?

    media_url.presence
  end

  def media_mime_with_fallback
    return nil unless media?

    media_mime.presence
  end

  def has_source_id?
    source_message_id.present?
  end

  private

  def generate_group_id
    self.group_id = self.class.generate_bulk_group_id
  end

  def self.generate_bulk_group_id
    last_group = maximum(:group_id) || 0
    last_group + 1
  end

  def set_default_content_type
    self.content_type ||= 'text'
  end

  def update_lead_interaction
    lead.update_last_interaction!
  end

  def update_lead_last_message
    attrs = {}
    attrs[:content] = content if lead.has_attribute?(:content)
    attrs[:content_type] = content_type if lead.has_attribute?(:content_type)
    attrs[:content_id] = source_message_id if lead.has_attribute?(:content_id)
    lead.update_columns(attrs) if attrs.any?
  end
end
