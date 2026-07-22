# frozen_string_literal: true

module Reports
  # commissioning-report 8.1 (D-R8) — os tetos de volume por documento, como
  # constantes NOMEADAS. O truncamento nunca é silencioso: quem excede vê o aviso
  # DENTRO do documento impresso (topo e rodapé) e cada tarefa truncada imprime
  # `(+N entradas anteriores omitidas)` — um toast sumiria antes da assinatura.
  class Budget
    # acima disso o documento renderiza inteiro, com aviso de escopo grande
    WARN_TASKS = 2_000
    # acima disso o histórico é truncado às KEEP_PER_TASK mais recentes por tarefa
    TRUNCATE_ADVANCES = 5_000
    # acima disso a emissão é recusada (422) ANTES de montar o payload
    MAX_TASKS = 8_000
    # quantas entradas por tarefa sobrevivem ao truncamento (as mais recentes)
    KEEP_PER_TASK = 10
  end
end
