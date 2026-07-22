# frozen_string_literal: true

module Api
  module V1
    # hierarchy-screens 3.1 (§3.7, D-D) — a busca da Visão Geral. Rota de DOMÍNIO:
    # exige `X-Workspace-Id`, o gate resolve o tenant e avalia a policy de leitura
    # ANTES do service. O escopo é a RLS (o service nem menciona `workspace_id`);
    # `q` ausente/vazio devolve lista vazia, nunca o workspace inteiro.
    class Search < Grape::API
      format :json
      helpers Api::V1::ControllerHelpers

      resource :search do
        route_setting :policy, policy: 'WorkspacePolicy', action: :show
        params do
          optional :q, type: String, default: ''
        end
        get do
          ::Hierarchy::SearchService.call(term: params[:q])
        end
      end
    end
  end
end
