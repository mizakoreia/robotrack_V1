# frozen_string_literal: true

# notification-preferences (D-P1/D-P2). Preferência de notificação de UMA pessoa
# sobre UM alvo da hierarquia (projeto/célula/robô). As garantias moram no banco
# (CHECK de um-alvo, FKs compostas, RLS forçada, índices únicos parciais); as
# validações aqui são ergonomia (422 legível em vez de PG::CheckViolation).
class NotificationSubscription < ApplicationRecord
  include WorkspaceScoped

  belongs_to :person, inverse_of: false

  STATES = %w[follow mute].freeze
  SCOPE_TYPES = %w[project cell robot].freeze

  validates :state, inclusion: { in: STATES }
  validate :exactly_one_scope

  # 'project' | 'cell' | 'robot' — o nível deste alvo.
  def scope_type
    return 'project' if scope_project_id
    return 'cell' if scope_cell_id

    'robot' if scope_robot_id
  end

  def scope_id
    scope_project_id || scope_cell_id || scope_robot_id
  end

  private

  def exactly_one_scope
    present = [scope_project_id, scope_cell_id, scope_robot_id].compact.size
    return if present == 1

    errors.add(:base, 'exatamente um alvo (projeto, célula ou robô) é obrigatório')
  end
end
