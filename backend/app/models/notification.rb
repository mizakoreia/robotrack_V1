# frozen_string_literal: true

# in-app-notifications (D-N2). A coluna `type` é o ENUM de negócio
# (assign/progress/done), NÃO o discriminador de STI do Rails — daí
# `inheritance_column = nil`. As invariantes 4 e 8 são de banco (triggers/CHECK).
class Notification < ApplicationRecord
  self.inheritance_column = nil

  # realtime-collaboration 3.6 / in-app-notifications (EXECUCAO §"tempo real"):
  # a notificação nova é entregue ao vivo consumindo o WorkspaceChannel de D6. O
  # front invalida `['ws', wsId, 'notifications']` ao receber `notification.created`
  # e refaz o fetch (escopado ao próprio destinatário). Só `:created` publica —
  # marcar-como-lida (update) e expurgo (destroy) NÃO viram evento de workspace.
  include RealtimePublishable
  realtime_publishes :created

  belongs_to :workspace
  belongs_to :recipient, class_name: 'Person', foreign_key: :recipient_person_id, inverse_of: false
  belongs_to :actor, class_name: 'Person', foreign_key: :actor_person_id, inverse_of: false

  TYPES = %w[assign progress done].freeze

  # in-app-notifications 8.1 (D-N10) — elegível a expurgo: LIDA há mais de 90 dias.
  # Uma NÃO lida de 730 dias NÃO consta (o usuário ainda não a viu). Ordenado por
  # `recorded_at` (a coluna do índice de retenção idx_notifications_retention).
  # O cron de expurgo mora em delivery-and-observability (Ops::RetentionPurge).
  scope :purgeable, -> { where(read: true).where(arel_table[:recorded_at].lt(90.days.ago)) }
end
