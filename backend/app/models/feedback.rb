# frozen_string_literal: true

# send-feedback — uma mensagem de feedback do beta enviada de dentro do app. As
# garantias moram no banco (workspace_id NOT NULL + RLS forçada, CHECK de tamanho
# da mensagem, CHECK de context = objeto); as validações aqui são ergonomia (422
# legível em vez de PG::CheckViolation).
#
# `workspace_id` é auto-atribuído pelo `WorkspaceScoped` a partir do contexto de
# tenant corrente — NUNCA vem do cliente. `user_id` é o autor (opcional; FK global
# a `users`, SET NULL na exclusão do usuário) e é gravado pelo endpoint a partir do
# bearer, não do corpo.
class Feedback < ApplicationRecord
  include WorkspaceScoped

  # Autor: FK GLOBAL a `users` (não a `people`), por isso `optional` e sem escopo
  # de workspace. Pode ficar nulo se o usuário for removido (ON DELETE SET NULL).
  belongs_to :user, optional: true

  MESSAGE_MAX = 4000

  validates :message, presence: true, length: { maximum: MESSAGE_MAX }
  validate :context_is_object

  private

  def context_is_object
    return if context.is_a?(Hash)

    errors.add(:context, 'deve ser um objeto')
  end
end
