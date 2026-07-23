# frozen_string_literal: true

# delivery-and-observability 1.2 — gera backend/.env.example a partir do registro
# único (config/env_schema.rb). Rodar após qualquer mudança no schema; o spec de
# 1.4 falha o CI se o arquivo versionado divergir do schema.
namespace :env do
  desc 'Gera backend/.env.example a partir de config/env_schema.rb'
  task :example do
    require_relative '../../config/env_schema'
    path = File.expand_path('../../.env.example', __dir__)
    File.write(path, EnvSchema.render_dotenv)
    puts "escrito #{path} (#{EnvSchema.entries.size} variáveis)"
  end
end
