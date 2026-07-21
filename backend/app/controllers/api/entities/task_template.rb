# frozen_string_literal: true

module Api
  module Entities
    # task-catalog 4.2 (§1.4 item 3, D-TC-5) — a resposta expõe `appFilters` em
    # camelCase, divergente do snake_case do resto da API: é o que o cliente
    # legado espera, e o nome antigo `apps` morre na fronteira do backend (nunca
    # aparece aqui). `weight` sai como inteiro quando integral (`1`, não `1.0`) —
    # o catálogo padrão é todo peso 1 e a tela mostra o número cru.
    class TaskTemplate < Grape::Entity
      expose :id
      expose :cat
      expose :desc
      expose(:weight) { |t, _| t.weight == t.weight.to_i ? t.weight.to_i : t.weight.to_f }
      expose(:appFilters) { |t, _| Array(t.app_filters) }
    end
  end
end
