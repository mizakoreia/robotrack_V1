# frozen_string_literal: true

module Ops
  # Contrato de `key` de alerta (delivery-and-observability 5.4). Registro do
  # formato das chaves que OUTRAS capacidades consomem, para que a deduplicação
  # seja previsível entre ondas: a mesma condição sempre gera a mesma `key`.
  #
  # Consumidores declarados:
  #   progress-rollup (D5)     — divergência de cache de progresso por recurso
  #   offline-pwa (D7)         — falha de reconciliação/drenagem da fila
  #   workspace-invitations    — falha de entrega de e-mail de convite
  module AlertKeys
    # `progress_cache_divergence:<workspace_id>` — D5 chega na Onda 6 e encontra
    # este formato já definido; a dedup por workspace evita ruído.
    def self.progress_cache_divergence(workspace_id)
      "progress_cache_divergence:#{workspace_id}"
    end

    # `offline_queue_reconcile_failure:<workspace_id>` — D7.
    def self.offline_queue_reconcile_failure(workspace_id)
      "offline_queue_reconcile_failure:#{workspace_id}"
    end

    # `invitation_delivery_failure:<invitation_id>` — workspace-invitations.
    def self.invitation_delivery_failure(invitation_id)
      "invitation_delivery_failure:#{invitation_id}"
    end
  end
end
