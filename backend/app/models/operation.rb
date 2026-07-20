# frozen_string_literal: true

class Operation < ApplicationRecord
  has_many :leads, class_name: 'Lead', foreign_key: 'operation_id'

  validates :key, presence: true, uniqueness: true
  validates :title, presence: true
  validates :description, presence: true, allow_blank: true

  before_validation :ensure_keywords_array
  before_create :generate_smart_id
  validate :keywords_uniqueness_across_operations

  def self.by_any_id(id)
    return nil if id.blank?

    if id.to_s.match?(/^\d+$/)
      find_by(id: id)
    else
      find_by(smart_id: id)
    end
  end

  def self.prepare_ordering(ordering_keys, ordering_style)
    orderings = []
    ordering_keys.each_with_index do |key, index|
      key_style = ordering_style[index]
      ordering = "#{get_ordering_key(key)} #{get_ordering_style(key_style)}"
      orderings << ordering
    end
    orderings.compact.join(', ')
  end

  def self.get_ordering_key(ordering_key)
    case ordering_key
    when 'key' then 'key'
    when 'title' then 'title'
    when 'active' then 'active'
    when 'created_at' then 'created_at'
    when 'updated_at' then 'updated_at'
    else 'created_at'
    end
  end

  def self.get_ordering_style(key_style)
    case key_style
    when 'up' then 'ASC'
    when 'down' then 'DESC'
    else 'DESC'
    end
  end

  def keywords_array
    return [] if keywords.blank?
    return keywords if keywords.is_a?(Array)

    begin
      JSON.parse(keywords)
    rescue StandardError
      []
    end
  end

  def keywords_array=(value)
    self.keywords = if value.is_a?(Array)
                      value
                    else
                      []
                    end
  end

  def add_keyword(keyword)
    return if keyword.blank?

    current = keywords_array
    keyword = keyword.strip

    return if current.include?(keyword)

    current << keyword
    self.keywords = current
  end

  def remove_keyword(keyword)
    return if keyword.blank?

    current = keywords_array
    keyword = keyword.strip

    return unless current.include?(keyword)

    current.delete(keyword)
    self.keywords = current
  end

  def keywords_count
    keywords_array.size
  end

  def matches_text?(text)
    return false if text.blank? || keywords_array.empty?

    keywords_array.any? do |pattern|
      regex = Regexp.new(pattern, Regexp::IGNORECASE)
      regex.match?(text)
    rescue RegexpError
      text.downcase.include?(pattern.downcase)
    end
  end

  def self.find_by_text(text)
    return nil if text.blank?

    Operation.where(active: true).find { |operation| operation.matches_text?(text) }
  end

  def update_leads_count!
    return unless ActiveRecord::Base.connection.column_exists?(:operations, :leads_count)

    count = Lead.where(operation_id: id).count
    update_columns(leads_count: count)
  end

  private

  def ensure_keywords_array
    self.keywords ||= []
  end

  def generate_smart_id
    return if smart_id.present?

    loop do
      random_id = "OP-#{SecureRandom.alphanumeric(10).upcase}"
      unless Operation.exists?(smart_id: random_id)
        self.smart_id = random_id
        break
      end
    end
  end

  def keywords_uniqueness_across_operations
    return if keywords_array.blank?

    keywords_array.each do |keyword|
      next if keyword.blank?

      conflict = Operation.where.not(id: id).where('keywords @> ?', [keyword].to_json).first
      if conflict
        errors.add(:keywords,
                   "A palavra-chave '#{keyword}' já está sendo usada na operação '#{conflict.title}' (#{conflict.key})")
      end
    end
  end
end
