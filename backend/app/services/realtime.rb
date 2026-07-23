# frozen_string_literal: true

# realtime-collaboration — namespace do tempo real e utilitários de request/
# transação. `Realtime::PublisherService`, `Realtime::CableTicketService` vivem
# sob este módulo; aqui ficam os helpers de supressão (3.5) e de execução
# pós-commit da transação corrente (usado pela publicação agregada).
module Realtime
  module_function

  # Suprime os eventos por linha do concern dentro do bloco (3.5). Usado por um
  # caminho em massa que mute linha a linha via callbacks, deixando o agregado
  # terminal como único envelope. Reentrante (restaura o valor anterior).
  def suppress
    prev = Current.suppress_realtime
    Current.suppress_realtime = true
    yield
  ensure
    Current.suppress_realtime = prev
  end

  def suppressed?
    Current.suppress_realtime == true
  end

  # Executa `block` quando a transação corrente COMMITAR de verdade (após o
  # COMMIT); se não houver transação aberta, executa já. É o que permite a
  # publicação agregada (batch de robôs, reset) sair pós-commit igual aos eventos
  # do concern — antes do commit, o cliente refetcharia linhas ainda não
  # persistidas. Sem transação (ex.: console/job solto), roda inline.
  def after_commit(&block)
    conn = ActiveRecord::Base.connection
    if conn.transaction_open?
      conn.add_transaction_record(TransactionFinalizer.new(block))
    else
      yield
    end
  end

  # Registro sintético que o AR enfileira na transação: dispara o callback só no
  # commit real, no-op no rollback. É o mecanismo do `after_commit_everywhere`,
  # com as assinaturas que o AR 8 invoca (keywords absorvidas por `**`).
  class TransactionFinalizer
    def initialize(callback)
      @callback = callback
    end

    def committed!(*, **)
      @callback.call
    end

    def before_committed!(*, **); end
    def rolledback!(*, **); end
    def add_to_transaction(*, **); end
    def trigger_transactional_callbacks? = true
    def has_transactional_callbacks? = true
  end
end
