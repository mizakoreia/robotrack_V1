# frozen_string_literal: true

# Base das policies de recurso, no idioma singleton dos services do template
# (`class << self`, D3.1). Substitui o piso de instância deixado por
# `workspace-invitations` (ApplicationPolicy com `role:` kwarg).
#
# Cada policy declara seus predicados com `permits`, mapeando cada operação
# para UMA action da matriz §4.1 — a policy não compara papel, não lê `User`
# e não tem predicado default: operação não declarada = NoMethodError, que é
# fail-closed mais barulhento do que um `false` silencioso. Predicado que
# precise de checagem além da matriz (ex.: destinatário de notificação)
# sobrescreve o método e continua consultando a matriz primeiro.
class BasePolicy
  class << self
    # Levanta em vez de retornar false: NotFound para quem nem é membro
    # (vira 404 — D3.6), Forbidden para membro sem papel suficiente (403).
    def authorize!(context, action, resource = nil)
      raise ::Authorization::NotFound unless context.member?
      raise ::Authorization::Forbidden unless public_send(:"#{action}?", context, resource)

      true
    end

    private

    # permits index?: :read_workspace, destroy?: :manage_commissioning
    def permits(map)
      map.each do |predicate, matrix_action|
        define_singleton_method(predicate) do |context, _resource = nil|
          PermissionMatrix.allows?(matrix_action, context.role)
        end
      end
    end
  end
end
