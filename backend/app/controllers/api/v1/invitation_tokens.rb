# frozen_string_literal: true

module Api
  module V1
    # code-only-invites §"Aceite/preview por código" — o convite é aceito e
    # pré-visualizado EXCLUSIVAMENTE por CÓDIGO (o link por token foi removido).
    #
    # As rotas por código vivem fora do mundo de tenant, e isso é deliberado: o
    # convidado ainda não é membro de workspace nenhum, então exigir
    # `X-Workspace-Id` tornaria o aceite impossível. A isenção é DECLARADA em
    # `Api::Root::TENANT_EXEMPT_ROUTES`.
    #
    # Não há papel de workspace a consultar aqui: a pré-visualização é PÚBLICA
    # (allowlist `config/authorization/public_routes.yml`) e o aceite declara
    # `access: :authenticated` — sua autorização É a invariante 6, avaliada
    # dentro da transação com a linha travada.
    class InvitationTokens < Grape::API
      format :json
      helpers Api::V1::ControllerHelpers

      # `Referrer-Policy: no-referrer` nas rotas de convite (6.3): defesa em
      # profundidade — mesmo sem token na URL, nada de credencial de convite deve
      # vazar pelo cabeçalho `Referer` de recurso externo carregado da resposta.
      before do
        header 'Referrer-Policy', 'no-referrer'
      end

      resource :invitations do
        # code-only-invites: o único caminho de convite é por CÓDIGO. `POST` mesmo
        # no preview: o par código + e-mail viaja no CORPO, nunca em query string
        # (regra de privacidade da casa).
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
      end
    end
  end
end
