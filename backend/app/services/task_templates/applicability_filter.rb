# frozen_string_literal: true

module TaskTemplates
  # task-catalog 2.3 (§2.5, D-TC-2) — a predicate de aplicabilidade, em UM lugar
  # e em DUAS linguagens.
  #
  # Um template vale para um robô quando: `app_filters` está vazio, OU contém
  # `"Misto / Geral"`, OU contém `"Todas"`, OU contém a Aplicação do robô.
  #
  # As duas sentinelas continuam aqui mesmo com a normalização de escrita
  # (D-TC-2) porque o banco pode receber linha por outro caminho — importador
  # legado (§1.4 item 3), console, restauração de backup. A versão simplificada
  # `app_filters = '{}' OR application = ANY(app_filters)` faria um template
  # `{"Todas"}` gravado direto no banco SUMIR para todo robô.
  #
  # Duas implementações do mesmo predicado divergirem é o modo de falha que faz
  # robô criado em lote e robô sincronizado terem conjuntos de tarefas
  # diferentes — por isso a tabela de casos do spec roda contra as duas.
  module ApplicabilityFilter
    CURINGAS = ['Misto / Geral', 'Todas'].freeze

    # Versão Ruby: decide sobre um template já carregado.
    def self.applicable?(template, application)
      filtros = Array(template.app_filters)
      return true if filtros.empty?
      return true if filtros.any? { |f| CURINGAS.include?(f) }

      filtros.include?(application)
    end

    # Versão SQL: mesma regra como relation, para não carregar o catálogo inteiro
    # em memória na criação em lote (robot-tasks) e na sincronização (§2.6).
    def self.scope_for(application, relation = TaskTemplate.all)
      relation.where(<<~SQL.squish, curingas: CURINGAS, application: application)
        cardinality(app_filters) = 0
        OR app_filters && ARRAY[:curingas]::text[]
        OR :application = ANY(app_filters)
      SQL
    end
  end
end
