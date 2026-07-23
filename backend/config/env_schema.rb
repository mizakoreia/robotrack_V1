# frozen_string_literal: true

# Registro ÚNICO de variáveis de ambiente (delivery-and-observability 1.1).
#
# Fonte auditável do que a app consome do ambiente: nome, tipo, em quais
# ambientes é OBRIGATÓRIA, o default (só para dev/test), a origem, e uma linha de
# ajuda para o `.env.example`. Duas coisas moram aqui:
#   1. O guarda de boot (initializer) aborta `staging`/`production` listando TODAS
#      as ausentes de uma vez — subir sem `ACTION_CABLE_URL` falha o boot em vez de
#      assumir `wss://example.com/cable` e quebrar o WebSocket de todos sem log.
#   2. O `.env.example` é GERADO daqui (rake), então documentação e código não
#      divergem — um spec falha se o arquivo versionado sair de sincronia.
#
# Sem chaves de Asaas/WhatsApp: aqueles módulos foram removidos do porte.
module EnvSchema
  Entry = Struct.new(:name, :type, :required_in, :default, :help, keyword_init: true) do
    def required_in?(env)
      required_in.include?(env.to_sym)
    end
  end

  ENTRIES = [
    # ── Banco ────────────────────────────────────────────────────────────────
    Entry.new(
      name: 'DATABASE_URL', type: :url, required_in: %i[production staging],
      default: 'postgres://robotrack_app:app_dev_pw@localhost/robotrack_dev',
      help: 'URL do Postgres da aplicação (role robotrack_app, NOBYPASSRLS).'
    ),
    # ── Segredo ──────────────────────────────────────────────────────────────
    Entry.new(
      name: 'SECRET_KEY_BASE', type: :string, required_in: %i[production staging],
      default: nil, help: 'Chave-base do Rails. Obrigatória fora de dev/test.'
    ),
    # ── Redis (isolamento por função entra no G3) ────────────────────────────
    Entry.new(
      name: 'REDIS_URL', type: :url, required_in: %i[production staging],
      default: 'redis://localhost:6379/1',
      help: 'Redis base; em dev serve de fallback para as URLs por função (cache/fila/cable).'
    ),
    # Isolamento de Redis por função (3.1): cache pode `allkeys-lru` evictar; fila
    # e cable NÃO podem perder dado. Em produção cada um é uma instância/db própria;
    # em dev caem no REDIS_URL. Obrigatórias em produção/staging → o guarda de
    # topologia (redis_topology.rb) ainda proíbe duas apontando para o mesmo lugar.
    Entry.new(name: 'REDIS_CACHE_URL', type: :url, required_in: %i[production staging],
              default: nil, help: 'Redis do cache (evictável). Fallback REDIS_URL em dev.'),
    Entry.new(name: 'REDIS_QUEUE_URL', type: :url, required_in: %i[production staging],
              default: nil, help: 'Redis da fila Sidekiq (não-evictável). Fallback REDIS_URL em dev.'),
    Entry.new(name: 'REDIS_CABLE_URL', type: :url, required_in: %i[production staging],
              default: nil, help: 'Redis do ActionCable (pub/sub). Fallback REDIS_URL em dev.'),
    # ── ActionCable / CORS ───────────────────────────────────────────────────
    Entry.new(
      name: 'ACTION_CABLE_URL', type: :url, required_in: %i[production staging],
      default: nil, help: 'URL pública do WebSocket (wss://.../cable). SEM default em produção.'
    ),
    Entry.new(
      name: 'CORS_ORIGINS', type: :csv, required_in: %i[production staging],
      default: nil, help: 'Origens permitidas, separadas por vírgula.'
    ),
    # ── Observabilidade ──────────────────────────────────────────────────────
    Entry.new(name: 'METRICS_TOKEN', type: :string, required_in: %i[production staging],
              default: nil, help: 'Bearer token do /metrics (Prometheus). Sem ele o endpoint responde 401.'),
    Entry.new(name: 'SENTRY_DSN', type: :string, required_in: [], default: nil,
              help: 'DSN do Sentry. Ausente = rastreio de exceção desligado (dev/test).'),
    Entry.new(name: 'ALERT_WEBHOOK_URL', type: :url, required_in: [], default: nil,
              help: 'Webhook de alerta (warning/critical). Ausente = só log estruturado.'),
    Entry.new(name: 'ALERT_PAGER_URL', type: :url, required_in: [], default: nil,
              help: 'Pager de alerta (critical). Ausente = critical degrada para log+Sentry.'),
    # ── Rate limit por classe (delivery-and-observability 7.3) ────────────────
    Entry.new(name: 'RATE_LIMIT_READ', type: :int, required_in: [], default: '300',
              help: 'Leituras (GET /api) por minuto por identidade.'),
    Entry.new(name: 'RATE_LIMIT_WRITE', type: :int, required_in: [], default: '120',
              help: 'Escritas (não-GET /api) por minuto por identidade.'),
    Entry.new(name: 'RATE_LIMIT_ROBOT_BATCH', type: :int, required_in: [], default: '10',
              help: 'Criação de robôs em lote por minuto.'),
    Entry.new(name: 'RATE_LIMIT_ADVANCE', type: :int, required_in: [], default: '60',
              help: 'Registros de avanço por minuto.'),
    Entry.new(name: 'RATE_LIMIT_AUTH', type: :int, required_in: [], default: '5',
              help: 'Tentativas de autenticação por minuto.'),
    Entry.new(name: 'RATE_LIMIT_REPORT', type: :int, required_in: [], default: '5',
              help: 'Gerações de relatório por minuto.'),
    # ── Toggles com default seguro ───────────────────────────────────────────
    Entry.new(name: 'FORCE_SSL', type: :bool, required_in: [], default: 'true',
              help: 'Redireciona http→https. Default ligado.'),
    Entry.new(name: 'COOKIES_SAME_SITE', type: :string, required_in: [], default: 'lax',
              help: 'SameSite dos cookies (lax/strict/none).'),
    Entry.new(name: 'RAILS_MAX_THREADS', type: :int, required_in: [], default: '10',
              help: 'Threads por processo Puma (= pool do Postgres).'),
    Entry.new(name: 'RAILS_LOG_TO_STDOUT', type: :bool, required_in: [], default: nil,
              help: 'Se presente, loga em STDOUT (coleta por plataforma).'),
    Entry.new(name: 'RAILS_SERVE_STATIC_FILES', type: :bool, required_in: [], default: nil,
              help: 'Serve estáticos pela app quando não há CDN.')
  ].freeze

  def self.entries
    ENTRIES
  end

  def self.find(name)
    ENTRIES.find { |e| e.name == name.to_s }
  end

  # Valor com default do schema. Em produção/staging uma obrigatória ausente já
  # teria abortado o boot; aqui o `default` só vale em dev/test.
  def self.fetch(name)
    entry = find(name) or raise ArgumentError, "variável não registrada: #{name}"
    value = ENV[entry.name]
    return value if value.present?

    entry.default
  end

  # URL do Redis por função com fallback ao REDIS_URL (dev). Em produção a por-
  # função é obrigatória (o guarda de boot cobra) e o fallback nunca é exercido.
  def self.redis_for(function)
    fetch("REDIS_#{function.to_s.upcase}_URL") || fetch('REDIS_URL')
  end

  # Obrigatórias ausentes no ambiente dado (para o guarda de boot).
  def self.missing(env)
    ENTRIES.select { |e| e.required_in?(env) && ENV[e.name].to_s.strip.empty? }
  end

  # Renderiza o `.env.example` a partir do schema (1.2). O arquivo versionado é
  # GERADO daqui; o spec de 1.4 regenera em memória e falha na divergência, então
  # adicionar variável sem regenerar quebra o CI nomeando o item.
  def self.render_dotenv
    header = [
      '# GERADO por `bundle exec rake env:example` a partir de config/env_schema.rb.',
      '# NÃO editar à mão — edite o schema e regenere. Sem chaves de serviços removidos do porte.',
      ''
    ]
    body = ENTRIES.flat_map do |e|
      escopo = e.required_in.empty? ? 'opcional' : "obrigatória em #{e.required_in.join('/')}"
      ["# #{e.help} (#{escopo})", "#{e.name}=#{e.default}", '']
    end
    (header + body).join("\n")
  end
end
