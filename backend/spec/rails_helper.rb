# frozen_string_literal: true

ENV['RAILS_ENV'] ||= 'test'
require File.expand_path('../config/environment', __dir__)
abort('The Rails environment is running in production mode!') if Rails.env.production?
require 'rspec/rails'
require 'webmock/rspec'
require 'vcr'
require 'database_cleaner/active_record'

Dir[Rails.root.join('spec/support/**/*.rb')].each { |file| require file }

RSpec.configure do |config|
  # Transacional continua sendo o padrão: é rápido e correto para 100% dos
  # specs atuais. Truncar tudo sempre multiplicaria o tempo da suíte por ~5 sem
  # resolver problema nenhum hoje — e progress-rollup e authorization-policies
  # vão adicionar specs de dataset grande (design §D-G).
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!

  config.include FactoryBot::Syntax::Methods

  config.before(:suite) do
    # Sem `maintain_test_schema!`: o schema de teste é migrado manualmente como
    # robotrack_migrator (a conexão de runtime robotrack_app não faz DDL/purge).
    # A truncation é obrigatória (não deletion): sob RLS, `DELETE` sem contexto
    # de tenant não remove nada. O `TRUNCATE ... RESTART IDENTITY` do
    # DatabaseCleaner exige ownership das sequences — resolvido em db/roles.sql
    # transferindo as sequences para robotrack_app. Ver EXECUCAO.md.
    DatabaseCleaner.clean_with(:truncation)
  end

  # Truncation onde a transação do RSpec não serve: specs de sistema/js (rodam em
  # outra conexão) e specs de tenancy, que exercitam o `SET LOCAL` do
  # `Tenant.with` — sob transação do RSpec o valor de sessão não seria descartado
  # no fim do bloco e os cenários de "variável é NULL após o contexto" mentiriam.
  config.around(:each) do |example|
    needs_truncation = example.metadata[:type] == :system ||
                       example.metadata[:js] ||
                       example.metadata[:tenancy]

    if needs_truncation
      DatabaseCleaner.strategy = :truncation
      self.class.use_transactional_tests = false
      DatabaseCleaner.cleaning { example.run }
    else
      example.run
    end
  end

  WebMock.disable_net_connect!(allow_localhost: true)

  VCR.configure do |c|
    c.cassette_library_dir = 'spec/cassettes'
    c.hook_into :webmock
    c.ignore_localhost = true
  end
end
