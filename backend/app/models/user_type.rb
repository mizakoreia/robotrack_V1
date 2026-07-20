# frozen_string_literal: true

# Modelo para tipos de usuários e suas hierarquias
class UserType < ApplicationRecord
  # Associations
  has_many :users, dependent: :restrict_with_error

  # Validations
  validates :name, presence: true, uniqueness: { case_sensitive: false }
  validates :description, presence: true
  validates :hierarchy_level, presence: true,
                              numericality: { only_integer: true, greater_than: 0 },
                              uniqueness: true

  # Callbacks
  before_save :normalize_name

  # Scopes
  scope :ordered_by_hierarchy, -> { order(hierarchy_level: :asc) }
  scope :higher_than, ->(level) { where('hierarchy_level < ?', level) }
  scope :lower_than, ->(level) { where('hierarchy_level > ?', level) }

  # Métodos de classe
  def self.og
    where('LOWER(name) = ?', 'og').first
  end

  def self.client
    where('LOWER(name) = ?', 'client').first
  end

  def self.seed_default_types!
    types = [
      { name: 'OG', description: 'Super Admin - Acesso total ao sistema', hierarchy_level: 1 },
      { name: 'client', description: 'Cliente - Usuário padrão do sistema', hierarchy_level: 2 }
    ]

    types.each do |type_attrs|
      type = where('LOWER(name) = ?', type_attrs[:name].downcase).first ||
             find_by(hierarchy_level: type_attrs[:hierarchy_level]) ||
             new
      type.name = type_attrs[:name]
      type.description = type_attrs[:description]
      type.hierarchy_level = type_attrs[:hierarchy_level]
      type.save!
    end
  end

  # Métodos de instância
  def og?
    name.to_s.downcase == 'og'
  end

  def client?
    name.to_s.downcase == 'client'
  end

  def higher_than?(other_type)
    hierarchy_level < other_type.hierarchy_level
  end

  def lower_than?(other_type)
    hierarchy_level > other_type.hierarchy_level
  end

  def same_level?(other_type)
    hierarchy_level == other_type.hierarchy_level
  end

  def display_name
    case name
    when 'OG'
      'Super Admin'
    when 'client'
      'Cliente'
    else
      name.humanize
    end
  end

  def permissions
    case name
    when 'OG'
      %w[read write delete manage_users manage_system view_all]
    when 'client'
      %w[read write update_profile]
    else
      %w[read]
    end
  end

  def can_access_admin_panel?
    hierarchy_level <= 1 # OG e tipos de nível 1
  end

  def can_manage_users?
    og? || permissions.include?('manage_users')
  end

  def can_manage_system?
    og? || permissions.include?('manage_system')
  end

  private

  def normalize_name
    self.name = name.downcase.strip if name.present?
  end
end
