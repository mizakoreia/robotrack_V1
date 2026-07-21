# frozen_string_literal: true

module Tasks
  # progress-advances 2.2 (§2.2, D-SM) — a máquina de estados status↔progresso,
  # como CÁLCULO PURO (não `aasm`, ver design D-SM). Recebe EXATAMENTE um de
  # `progress` XOR `status` e devolve o par `(status, progress)` resolvido, mais
  # `completed` (a transição chegou a 100 → o `CreateService` grava auditoria).
  #
  # Tabela-verdade de §2.2, direta e testável linha a linha:
  #   status=Concluído          → progress=100
  #   status=N/A                → progress=0
  #   status=Pendente           → progress=0
  #   status=Em Andamento       → progress inalterado
  #   progress=100              → status=Concluído (+ auditoria)
  #   0<progress<100            → status=Em Andamento
  #   progress=0 e status≠N/A   → status=Pendente
  #   progress=0 e status=N/A   → status=N/A (PRESERVADO — a exceção que o WBS perdia)
  #
  # A persistência e a transação são do `TaskAdvances::CreateService` (G3); aqui
  # só a resolução.
  module ApplyTransitionService
    STATUSES = ::Task::STATUSES # ['Pendente','Em Andamento','Concluído','N/A']

    Result = Struct.new(:status, :progress, :completed, keyword_init: true)

    # @return [Result]
    def self.resolve(current_status:, current_progress:, progress: nil, status: nil)
      if (progress.nil?) == (status.nil?)
        raise ArgumentError, 'informe EXATAMENTE um de progress XOR status'
      end

      status ? from_status(status, current_progress) : from_progress(progress.to_i, current_status)
    end

    def self.from_status(status, current_progress)
      unless STATUSES.include?(status)
        raise ArgumentError, "status inválido: #{status.inspect}"
      end

      case status
      when 'Concluído'    then Result.new(status: 'Concluído', progress: 100, completed: true)
      when 'N/A'          then Result.new(status: 'N/A', progress: 0, completed: false)
      when 'Pendente'     then Result.new(status: 'Pendente', progress: 0, completed: false)
      when 'Em Andamento' then Result.new(status: 'Em Andamento', progress: current_progress, completed: false)
      end
    end

    def self.from_progress(progress, current_status)
      unless progress.between?(0, 100)
        raise ArgumentError, "progress fora de 0..100: #{progress}"
      end

      if progress == 100
        Result.new(status: 'Concluído', progress: 100, completed: true)
      elsif progress.positive?
        Result.new(status: 'Em Andamento', progress: progress, completed: false)
      elsif current_status == 'N/A'
        Result.new(status: 'N/A', progress: 0, completed: false) # exceção preservada
      else
        Result.new(status: 'Pendente', progress: 0, completed: false)
      end
    end

    private_class_method :from_status, :from_progress
  end
end
