# frozen_string_literal: true

# realtime-collaboration 3.3 / D6.9 — o concern que torna um model de domínio
# "ao vivo": publica um envelope no `after_commit` de toda criação, atualização e
# exclusão. Um ponto único acoplado ao ciclo de vida do model (auditável e
# testável pela cobertura de 3.6), em vez de espalhar `publish` pelos services de
# sete capacidades — a primeira que esquecesse reproduziria o bug que originou
# esta proposta: uma tela que deixou de ser ao vivo sem ninguém notar.
#
# Por que `after_commit`, não dentro da transação: publicar antes do commit
# entrega ponteiro para linha que pode sofrer rollback. A supressão (3.5) é
# capturada NA transação (os callbacks não-commit rodam durante o save, quando o
# flag de `Realtime.suppress` ainda vale) e honrada no commit — o `after_commit`
# roda no fim da request, quando o bloco de supressão já saiu.
#
# Contrato do envelope (D6.2) — defaults aqui, cada model sobrescreve o que difere:
#   realtime_type_prefix  → prefixo do `type` ("task", "robot", "membership"…)
#   realtime_entity       → {kind:, id:} da entidade apontada
#   realtime_scope        → {project_id:, cell_id:, robot_id:} p/ a cadeia de rollup
#   realtime_workspace_id → o workspace do stream
module RealtimePublishable
  extend ActiveSupport::Concern

  included do
    # Quais ações do ciclo de vida publicam envelope. Default: as três (toda
    # entidade de domínio "cheia"). Um model pode restringir via `realtime_publishes`
    # — ex.: `Notification` publica só `:created`, porque o front mapeia apenas
    # `notification.created`; um `notification.updated`/`deleted` cairia no fallback
    # "tipo desconhecido" e invalidaria a subárvore INTEIRA do workspace.
    class_attribute :realtime_publish_actions, instance_accessor: false,
                    default: %i[created updated destroyed].freeze

    # Snapshot da supressão DENTRO da transação (o flag vale aqui; no commit, não).
    after_create  { @__realtime_suppressed = ::Realtime.suppressed? }
    after_update  { @__realtime_suppressed = ::Realtime.suppressed? }
    after_destroy { @__realtime_suppressed = ::Realtime.suppressed? }

    after_create_commit  { ::Realtime::PublisherService.publish_change(self, :created)   if __realtime_publish?(:created) }
    after_update_commit  { ::Realtime::PublisherService.publish_change(self, :updated)   if __realtime_publish?(:updated) }
    after_destroy_commit { ::Realtime::PublisherService.publish_change(self, :destroyed) if __realtime_publish?(:destroyed) }
  end

  class_methods do
    # Restringe quais ações publicam envelope (default: created/updated/destroyed).
    #   realtime_publishes :created   # só nascimento vira evento ao vivo
    def realtime_publishes(*actions)
      self.realtime_publish_actions = actions.map(&:to_sym).freeze
    end
  end

  # Publica esta ação? Não, se suprimida (3.5) ou fora do conjunto declarado.
  def __realtime_publish?(action)
    return false if @__realtime_suppressed

    self.class.realtime_publish_actions.include?(action)
  end

  def realtime_type_prefix
    self.class.name.underscore
  end

  # `type` do envelope. Default `<prefix>.<verbo>`; models cujo vocabulário difere
  # (Membership: created/role_changed/revoked) sobrescrevem.
  def realtime_event_type(action)
    "#{realtime_type_prefix}.#{::Realtime::PublisherService::VERB.fetch(action)}"
  end

  def realtime_entity
    { kind: self.class.name.underscore, id: id }
  end

  def realtime_scope
    {}
  end

  def realtime_workspace_id
    workspace_id
  end
end
