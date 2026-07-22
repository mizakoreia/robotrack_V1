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
