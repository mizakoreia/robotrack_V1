# frozen_string_literal: true

module Api
  module V1
    # workspace-invitations §"Pré-visualização pública" e §"Consumo atômico"
    # (tarefas 3.3, 3.4).
    #
    # As DUAS rotas por token vivem fora do mundo de tenant, e isso é deliberado:
    # o convidado ainda não é membro de workspace nenhum, então exigir
    # `X-Workspace-Id` tornaria o aceite impossível. A isenção é DECLARADA em
    # `Api::Root::TENANT_EXEMPT_ROUTES` (ciente de método, para não arrastar
    # junto o `DELETE /api/v1/invitations/:id`, que é rota de domínio normal).
    #
    # Não há papel de workspace a consultar aqui: a pré-visualização é PÚBLICA
    # (allowlist `config/authorization/public_routes.yml`) e o aceite declara
    # `access: :authenticated` — sua autorização É a invariante 6, avaliada
    # dentro da transação com a linha travada.
    class InvitationTokens < Grape::API
      format :json
      helpers Api::V1::ControllerHelpers

      # `Referrer-Policy: no-referrer` nas duas rotas por token (6.3): o token
      # está na URL, e sem isto qualquer recurso externo carregado a partir da
      # resposta levaria a URL inteira — com a credencial — no cabeçalho
      # `Referer`. O frontend faz o par disso trocando a URL por uma sem o token
      # (`history.replaceState`) assim que o guarda em sessionStorage.
      before do
        header 'Referrer-Policy', 'no-referrer'
      end

      resource :invitations do
        # invite-by-code (design D6): as rotas por CÓDIGO são declaradas ANTES de
        # `:token/accept` porque `POST /invitations/code/accept` casaria o padrão
        # `POST /invitations/:token/accept` com `token = "code"` — o Grape resolve
        # por ORDEM de declaração. `POST` mesmo no preview: o e-mail viaja no CORPO,
        # nunca em query string (regra de privacidade da casa).
        namespace :code do
          # POST /api/v1/invitations/code/preview — público, exige o par
          # (código + e-mail); resposta genérica quando o par não casa (anti-
          # colheita de phishing).
          params do
            requires :code, type: String
            requires :email, type: String
          end
          post :preview do
            result = ::Invitations::PreviewService.new(code: params[:code], email: params[:email]).call
            error!({ error: result[:error] }, result[:status]) unless result[:success]

            # POST por privacidade (e-mail no corpo), mas é uma LEITURA: 200, não o
            # 201 que o Grape assume para POST.
            status 200
            present result[:data], with: Api::Entities::InvitationPreview
          end

          # POST /api/v1/invitations/code/accept — autenticado, sem tenant. A
          # autorização É a invariante 6 (avaliada com a linha travada no
          # AcceptService); aqui só a autenticação conta. O corpo NÃO admite `role`.
          route_setting :policy, access: :authenticated
          params do
            requires :code, type: String
            requires :email, type: String
          end
          post :accept do
            result = ::Invitations::AcceptService.new(
              current_user: env['api.current_user'],
              code: params[:code],
              email: params[:email],
              extra_params: request.params
            ).call

            error!({ error: result[:error] }, result[:status]) unless result[:success]

            status 200
            result[:data]
          end
        end

        # GET /api/v1/invitations/:token — público (pré-login).
        params do
          requires :token, type: String
        end
        get ':token' do
          result = ::Invitations::PreviewService.new(token: params[:token]).call
          error!({ error: result[:error] }, result[:status]) unless result[:success]

          present result[:data], with: Api::Entities::InvitationPreview
        end

        # POST /api/v1/invitations/:token/accept — autenticado, sem tenant.
        # A autorização do aceite É a invariante 6 (avaliada com a linha
        # travada, dentro do AcceptService); aqui só a autenticação conta.
        route_setting :policy, access: :authenticated
        params do
          requires :token, type: String
        end
        post ':token/accept' do
          result = ::Invitations::AcceptService.new(
            current_user: env['api.current_user'],
            token: params[:token],
            requested_workspace_id: headers['X-Workspace-Id'] || headers['HTTP_X_WORKSPACE_ID'],
            extra_params: request.params
          ).call

          error!({ error: result[:error] }, result[:status]) unless result[:success]

          status 200
          result[:data]
        end
      end
    end
  end
end
