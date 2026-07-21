# frozen_string_literal: true

module Hierarchy
  # commissioning-hierarchy 5.1/5.3 (§2.9, D-H3, D-H4) — reordenação em LOTE.
  #
  # Uma transação renumera o escopo inteiro 0..n-1. O UNIQUE de position é
  # DEFERRABLE, então a renumeração não passa por posições fake. O advisory
  # lock do escopo (o MESMO de PositionScoped) serializa reordenações e
  # criações concorrentes. Conflito é detectado por CONJUNTO de ids — não por
  # lock_version, que nem é tocado: renomear e reordenar são ações
  # independentes (D-H9), e `update_all` não incrementa nada.
  #
  # Conjunto divergente (alguém criou/excluiu um irmão entre o carregamento da
  # tela e o drop) → 409 com o conjunto ATUAL em ordem, sem escrever nada.
  class ReorderService
    include ApiResponseHandler

    def initialize(model:)
      @model = model
    end

    def call(scope_id:, ordered_ids:)
      return error_response('invalid_ordered_ids', 422) if ordered_ids.blank?

      scope_column = @model.position_scope_column

      resultado = nil
      @model.transaction do
        @model.lock_position_scope!(scope_id)

        atuais = @model.where(scope_column => scope_id).order(:position).pluck(:id)
        if atuais.empty?
          resultado = error_response('not_found', 404)
          raise ActiveRecord::Rollback
        end

        if atuais.sort != ordered_ids.map(&:to_s).sort
          resultado = error_response('reorder_conflict', 409, details: { current_ids: atuais })
          raise ActiveRecord::Rollback
        end

        ordered_ids.each_with_index do |id, index|
          # Rails 8 incrementa lock_version em update_all a menos que a chave
          # venha explícita — e reordenar NÃO é edição do item (D-H9).
          @model.where(id: id).update_all(position: index, lock_version: Arel.sql('lock_version'))
        end

        resultado = success_response(
          { records: @model.where(scope_column => scope_id).order(:position).to_a }, 200
        )
      end
      resultado
    end
  end
end
