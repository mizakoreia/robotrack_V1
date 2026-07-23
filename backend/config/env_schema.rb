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
      help: 'Redis base; em produção é sobreposto pelas URLs por função (cache/fila/cable).'
    ),
    # ── ActionCable / CORS ───────────────────────────────────────────────────
    Entry.new(
      name: 'ACTION_CABLE_URL', type: :url, required_in: %i[production staging],
      default: nil, help: 'URL pública do WebSocket (wss://.../cable). SEM default em produção.'
    ),
    Entry.new(
      name: 'CORS_ORIGINS', type: :csv, required_in: %i[production staging],
      default: nil, help: 'Origens permitidas, separadas por vírgula.'
    ),
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
