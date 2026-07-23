# frozen_string_literal: true

# realtime-collaboration 1.3 — Isolamento do adapter do ActionCable em produção.
#
# Com `adapter: async` (o default do Rails quando o `cable.yml` não resolve para
# redis) o broadcast NÃO sai do processo: cada worker do Puma tem o próprio pubsub
# em memória, e um evento publicado no `after_commit` de um worker nunca chega ao
# socket aberto noutro. O sistema sobe "ao vivo" só na aparência — a regressão
# exata que esta proposta existe para impedir. Em produção, abortamos o boot em
# vez de servir nesse estado; em development/test o adapter é `redis`/`test` por
# construção, então a guarda não interfere.
if Rails.env.production?
  Rails.application.config.after_initialize do
    cable = ActionCable.server.config.cable || {}
    adapter = (cable['adapter'] || cable[:adapter]).to_s

    unless adapter == 'redis'
      abort(
        "[action_cable_adapter_guard] adapter do ActionCable em produção deve ser " \
        "'redis' (resolvido: #{adapter.inspect}). Broadcast com '#{adapter}' não sai " \
        'do processo — configure CABLE_REDIS_URL/cable.yml antes de subir.'
      )
    end
  end
end
