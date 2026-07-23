# frozen_string_literal: true

# progress-rollup 3.5 — o medidor de orçamento de query. Assina `sql.active_record`
# e conta os SELECT emitidos por um bloco (ignorando SCHEMA, transação e as
# queries do próprio harness). `expect { get ... }.to issue_at_most(2).queries`
# roda com 20 projetos — com 1 projeto um N+1 seria indistinguível do ótimo.
RSpec::Matchers.define :issue_at_most do |max|
  chain(:queries) {}
  supports_block_expectations

  match do |block|
    @queries = []
    sub = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
      name = payload[:name].to_s
      sql = payload[:sql].to_s
      next if name =~ /SCHEMA|TRANSACTION/i
      next unless sql =~ /\A\s*SELECT/i
      next if sql =~ /\A\s*SELECT\s+1\b/i # `SELECT 1` de checagem de conexão

      @queries << sql
    end
    begin
      block.call
    ensure
      ActiveSupport::Notifications.unsubscribe(sub)
    end
    @queries.size <= max
  end

  failure_message do
    "esperava no máximo #{max} SELECT, contou #{@queries.size}:\n" +
      @queries.map { |q| "  #{q.gsub(/\s+/, ' ')[0, 100]}" }.join("\n")
  end
end

# quality-and-accessibility 8.2 — contagem crua de SELECT de um bloco, para medir a
# VARIAÇÃO com o tamanho do dataset (a assinatura real de N+1: teto absoluto passa
# folgado com dataset pequeno; o que morde é a contagem crescer com N). Limpa o
# cache de query do AR ANTES de medir, senão a 2ª amostra herda resultados em cache
# e a variação some. Mesma filtragem do `issue_at_most` (sem SCHEMA/TRANSACTION/`SELECT 1`).
module QueryCountHelper
  def count_queries
    ActiveRecord::Base.connection.clear_query_cache
    queries = []
    sub = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
      name = payload[:name].to_s
      sql = payload[:sql].to_s
      next if name =~ /SCHEMA|TRANSACTION/i
      next unless sql =~ /\A\s*SELECT/i
      next if sql =~ /\A\s*SELECT\s+1\b/i

      queries << sql
    end
    begin
      ActiveRecord::Base.uncached { yield }
    ensure
      ActiveSupport::Notifications.unsubscribe(sub)
    end
    queries.size
  end
end

RSpec.configure { |c| c.include QueryCountHelper }
