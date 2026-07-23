# frozen_string_literal: true

module Ops
  # Canal ÚNICO de alerta operacional (delivery-and-observability 5.1/5.2). Todo
  # alerta passa por aqui: roteamento por severidade, deduplicação atômica no Redis
  # de cache (a mesma `key` não notifica duas vezes na janela de 1h) e blindagem
  # contra a queda do destino (um webhook 500 NÃO vira exceção no chamador — uma
  # reconciliação de D5 não pode falhar porque o Slack caiu).
  #
  # Roteamento por severidade:
  #   :info     → só log estruturado (nem webhook, nem pager)
  #   :warning  → log + webhook
  #   :critical → log + webhook + pager; sem PAGER degrada para log+Sentry
  class AlertService
    SEVERITIES = %i[info warning critical].freeze
    DEDUP_TTL = 3600 # 1h

    def self.instance
      @instance ||= new
    end

    def self.raise_alert(**kwargs)
      instance.raise_alert(**kwargs)
    end

    # `reset!` só para teste (troca as dependências injetadas).
    def self.reset!(**deps)
      @instance = new(**deps)
    end

    def initialize(cache: nil, webhook: nil, pager: nil, logger: nil, sentry: nil)
      # `Rails.cache` é o redis_cache_store em produção (atômico via `unless_exist`)
      # e MemoryStore em teste — o dedup funciona nos dois sem um cliente Redis cru.
      @cache = cache || Rails.cache
      @webhook = webhook || ->(payload) { deliver_webhook(payload) }
      @pager = pager || ->(payload) { deliver_pager(payload) }
      @logger = logger || Rails.logger
      @sentry = sentry
    end

    def raise_alert(key:, severity:, message:, context: {})
      severity = severity.to_sym
      raise ArgumentError, "severidade inválida: #{severity}" unless SEVERITIES.include?(severity)

      return :suppressed unless acquire?(key)

      payload = { key: key, severity: severity, message: message, context: context, at: Time.now.utc.iso8601 }
      log(payload)
      notify(severity, payload)
      :delivered
    end

    private

    # `write unless_exist`: devolve true só na PRIMEIRA aquisição na janela; nas
    # repetições a chave já existe e devolve false (suprime). Atômico no Redis —
    # duas abas/processos não notificam os dois.
    def acquire?(key)
      @cache.write("alert:#{key}", 1, unless_exist: true, expires_in: DEDUP_TTL)
    rescue StandardError => e
      # Cache fora não pode engolir um alerta: sem dedup, deixa passar e loga.
      @logger.warn("[alert] dedup indisponível (#{e.class}); alerta segue sem dedup")
      true
    end

    def notify(severity, payload)
      return if severity == :info

      shielded { @webhook.call(payload) }
      return unless severity == :critical

      if pager_configured?
        shielded { @pager.call(payload) }
      else
        # Degradação (5.4): sem pager, critical NÃO levanta exceção — vira log+Sentry.
        @logger.error("[alert] CRITICAL sem PAGER configurado: #{payload[:key]}")
        @sentry&.call(payload)
      end
    end

    # Blindagem: a falha de entrega vai para o log estruturado e NÃO propaga.
    def shielded
      yield
    rescue StandardError => e
      @logger.error({ event: 'alert_delivery_failed', error: e.class.name, message: e.message }.to_json)
    end

    def log(payload)
      @logger.info(payload.merge(event: 'ops_alert').to_json)
    end

    def pager_configured?
      ENV['ALERT_PAGER_URL'].present?
    end

    def deliver_webhook(payload)
      url = ENV['ALERT_WEBHOOK_URL']
      return if url.blank?

      Net::HTTP.post(URI(url), payload.to_json, 'Content-Type' => 'application/json')
    end

    def deliver_pager(payload)
      url = ENV['ALERT_PAGER_URL']
      return if url.blank?

      Net::HTTP.post(URI(url), payload.to_json, 'Content-Type' => 'application/json')
    end
  end
end
