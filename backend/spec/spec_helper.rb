# frozen_string_literal: true

require 'simplecov'
SimpleCov.start 'rails'

RSpec.configure do |config|
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Benchmarks de carga (`:slow`) ficam FORA do run padrão. São specs que semeiam
  # dezenas de milhares de linhas (ex.: progress/load_dataset_spec = 93k tasks) e
  # afirmam orçamentos de latência sensíveis ao tuning do Postgres — não pertencem
  # à suíte de todo dia nem ao `bundle exec rspec` de paridade. Rode sob demanda:
  #   SLOW=1 bundle exec rspec --tag slow
  config.filter_run_excluding :slow unless ENV['SLOW']
end
