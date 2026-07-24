# frozen_string_literal: true

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    # Default DEV/local: :5173 (vite dev), :3000 (backend), :4173 (vite PREVIEW —
    # o alvo obrigatório do E2E, que roda contra o build de produção servido).
    # Em produção CORS_ORIGINS é fornecido (env_schema), então este default não vale
    # lá; incluir :4173 aqui evita que todo E2E esbarre no preflight sem
    # access-control-allow-origin.
    origins ENV.fetch('CORS_ORIGINS', 'http://localhost:5173,http://localhost:3000,http://localhost:4173').split(',')
    resource '*',
             headers: :any,
             methods: %i[get post put patch delete options head],
             expose: ['Authorization'],
             max_age: 7200,
             credentials: true
  end
end
