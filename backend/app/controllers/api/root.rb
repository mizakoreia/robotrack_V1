# frozen_string_literal: true

require 'grape'
require_relative './v1/controller_helpers'
require 'grape-swagger'
require 'grape-swagger-entity'

module Api
  class Root < Grape::API
    format :json
    # Sem prefixo/version global; cada módulo define seu próprio prefixo e versão

    # Abre UMA transação em volta de cada rota de DOMÍNIO, dentro da qual o bloco
    # `before` emite o SET LOCAL do contexto de tenant (workspace-tenancy 4.2).
    use Tenant::TransactionMiddleware

    # Única lista de rotas servidas sem autenticação. Qualquer caminho fora
    # daqui exige `Authorization: Bearer` válido — não há header, env var ou
    # token de aplicação que desligue essa verificação.
    # Allowlist pública. Entradas são regex (qualquer método) OU pares
    # `['METHOD', regex]` quando a mesma rota é pública em um método e protegida
    # em outro — o caso de `/auth/v1/session`: `POST` (login) é público, `DELETE`
    # (logout) NÃO é, porque precisa do token para saber qual `jti` revogar (D4.8).
    PUBLIC_ROUTES = [
      %r{^/swagger_doc},
      %r{^/api/v1/countries/?$},
      # Auth pública, ANCORADA (D4.8): `session/?$` NÃO casa `session/renew`.
      ['POST', %r{^/auth/v1/session/?$}],
      ['POST', %r{^/auth/v1/registration/?$}],
      # Google OAuth por redirect Devise (D4.8). O request phase e o callback são
      # rotas Rails, fora da varredura Grape; a entrada aqui é defensiva.
      %r{^/users/auth/google_oauth2},
      # Pré-visualização do convite (workspace-invitations 3.4 / D-INV-6): o
      # token chega ANTES do login, e o convidado precisa saber para onde ele
      # leva. Só `GET`, e só com um segmento após `invitations/` — a listagem
      # (`GET /api/v1/invitations`) continua protegida, e o aceite (`POST`) exige
      # autenticação porque compara o e-mail do convite com o AUTENTICADO.
      ['GET', %r{^/api/v1/invitations/[^/]+/?$}]
    ].freeze

    def self.public_route?(method, path)
      PUBLIC_ROUTES.any? do |entry|
        if entry.is_a?(Array)
          entry[0] == method.to_s.upcase && entry[1].match?(path)
        else
          entry.match?(path)
        end
      end
    end

    # Rotas SEM contexto de tenant (allowlist explícita — tenant-isolation 4.2).
    # Toda rota fora daqui é de DOMÍNIO: exige `X-Workspace-Id`, resolve o papel
    # no servidor e roda dentro de uma transação com o contexto setado. Hoje NADA
    # é workspace-scoped por HTTP — o primeiro recurso de domínio (projects, a
    # jusante) cai fora desta lista e a spec de varredura (4.6) o obriga a se
    # declarar. `users`/`uploads`/`downloads` são globais do template (gestão OG);
    # se virarem tenant, saem daqui e a varredura cobra.
    #
    # Entradas são regex (qualquer método) OU pares `['METHOD', regex]`, mesma
    # forma de PUBLIC_ROUTES. O par existe por causa dos convites: a
    # pré-visualização (`GET /api/v1/invitations/:token`) e o aceite
    # (`POST /api/v1/invitations/:token/accept`) acontecem FORA de um workspace
    # corrente — o convidado ainda não é membro de nada —, enquanto
    # `DELETE /api/v1/invitations/:id` é rota de domínio comum e continua na
    # varredura de tenant. Sem ciência de método, a isenção de um arrastaria o
    # outro (workspace-invitations, decisão de execução 6).
    TENANT_EXEMPT_ROUTES = [
      %r{^/swagger_doc},
      %r{^/auth/},
      %r{^/api/v1/workspaces},
      %r{^/api/v1/users},
      %r{^/api/v1/countries},
      %r{^/api/v1/uploads},
      %r{^/api/v1/downloads},
      # Metadados globais (task-catalog 4.5): o enum de Aplicações é o mesmo para
      # todo tenant; a rota exige login (não é pública) mas não workspace-scoped.
      %r{^/api/v1/meta/},
      # Ticket do Cable (realtime-collaboration 1.1): o ticket é do usuário, não
      # de um workspace — exige login, mas não `X-Workspace-Id`. A autorização por
      # membership é do `WorkspaceChannel`, no `subscribed` de cada assinatura.
      %r{^/api/v1/cable_tickets/?$},
      ['GET',  %r{^/api/v1/invitations/[^/]+/?$}],
      ['POST', %r{^/api/v1/invitations/[^/]+/accept/?$}]
    ].freeze

    def self.tenant_exempt?(method, path)
      TENANT_EXEMPT_ROUTES.any? do |entry|
        if entry.is_a?(Array)
          entry[0] == method.to_s.upcase && entry[1].match?(path)
        else
          entry.match?(path)
        end
      end
    end

    helpers Api::V1::AuthorizationHelpers

    before do
      next if Api::Root.public_route?(request.request_method, request.path)

      # Autenticação centralizada por `Auth::TokenService.decode`, que verifica
      # assinatura, expiração E denylist (revogação). O caminho ÚNICO — sem
      # fallback via Warden::JWTAuth::TokenDecoder, que decodifica sem checar o
      # denylist e ressuscitaria um token revogado (identity-and-auth D4.1). Um
      # token no denylist chega aqui e vira 401.
      auth_header = headers['Authorization'] || headers['HTTP_AUTHORIZATION']
      error!({ error: 'unauthorized', message: 'Authorization header ausente' }, 401) if auth_header.blank?

      scheme, token = auth_header.split(' ')
      unless scheme == 'Bearer' && token.present?
        error!({ error: 'unauthorized', message: 'Formato do Authorization inválido' }, 401)
      end

      user = nil
      begin
        # `::Auth` (topo) — dentro de `module Api`, `Auth` resolveria para
        # `Api::Auth` (o namespace Grape da auth), que não tem TokenService.
        payload = ::Auth::TokenService.decode(token, verify_exp: true)
        user = User.find_by(id: payload['sub']) if payload && payload['sub']
      rescue StandardError
        user = nil
      end

      error!({ error: 'unauthorized', message: 'Token inválido' }, 401) unless user

      @current_user = user
      env['api.current_user'] = @current_user

      # Contexto de tenant das rotas de domínio (workspace-tenancy 4.2). Roda
      # dentro da transação aberta por Tenant::TransactionMiddleware.
      unless Api::Root.tenant_exempt?(request.request_method, request.path)
        ws_id = headers['X-Workspace-Id'] || headers['HTTP_X_WORKSPACE_ID']
        resolution = Workspaces::ResolveCurrentService.new(user: @current_user, workspace_id: ws_id).call
        error!({ error: resolution.error }, resolution.status) unless resolution.ok

        Tenant.apply!(workspace_id: resolution.workspace_id, user_id: @current_user.id)
        @current_workspace_id = resolution.workspace_id
        @current_role = resolution.role
        env['api.current_workspace_id'] = @current_workspace_id
        env['api.current_role'] = @current_role
      end

      # authorization-policies (D3.4): a decisão de autorização acontece AQUI,
      # uma vez por request, antes de qualquer service — INCONDICIONAL em todo
      # ambiente (a flag de rollout da própria change foi removida em 6.3).
      authorize_route!
    end

    helpers do
      def process_service_response(response)
        status response[:status]

        if (200..299).include?(response[:status])
          response[:data]
        else
          error_payload = { error: response[:error] || response[:message] }
          error_payload[:details] = response[:details] if response[:details]
          error!(error_payload, response[:status])
        end
      end

      attr_reader :current_user, :current_workspace_id, :current_role
    end

    # Montando os módulos da API (cada um com seu prefixo e versão)
    mount Api::Auth::V1::Base     # /auth/v1/*
    mount Api::V1::Base

    # Contrato de negação (authorization-policies 2.4 / D3.12): corpo de chave
    # única `error`, sem nome de policy, action ou papel. As strings pt-BR para
    # a UI vivem em config/locales/pt-BR.authorization.yml (D14) — o corpo da
    # negação NÃO as inclui, de propósito.
    rescue_from ::Authorization::Forbidden do
      error!({ error: 'forbidden' }, 403)
    end

    rescue_from ::Authorization::NotFound do
      error!({ error: 'not_found' }, 404)
    end

    # Fail-closed por ambiente (2.3 / D3.4). Rota sem declaração NUNCA responde
    # 200. Em development/test o 500 é BARULHENTO e distinguível: código
    # `undeclared_route` + o path ofensor no corpo — o Grape engole exceção
    # re-levantada dentro de rescue_from, então a "falha na cara de quem
    # escreveu o endpoint" é este corpo, mais o route-sweep que reprova em CI.
    # Em produção: 500 genérico sem detalhe, reportado ao rastreio.
    rescue_from ::Authorization::UndeclaredRouteError do |e|
      if Rails.env.development? || Rails.env.test?
        error!({ error: 'undeclared_route', message: e.message }, 500)
      else
        ErrorReporter.report(e, context: { path: request.path, method: request.request_method })
        error!({ error: 'internal_error' }, 500)
      end
    end

    # Único tratamento de erro da API — as cópias em Api::V1::Base e
    # Api::Auth::V1::Base foram removidas. O backtrace vai para o log, nunca
    # para o corpo da resposta.
    rescue_from :all do |e|
      request_id = env['action_dispatch.request_id'] || SecureRandom.uuid

      if e.is_a?(Grape::Exceptions::ValidationErrors)
        error!({ error: 'validation_error', message: 'Dados inválidos', details: e.errors, request_id: }, 400)
      end

      Rails.logger.error(
        {
          event: 'api_error',
          request_id:,
          exception: e.class.name,
          message: e.message,
          backtrace: Array(e.backtrace).first(30)
        }.to_json
      )

      ErrorReporter.report(e, context: { request_id:, path: request.path, method: request.request_method })

      error!({ error: 'internal_error', message: 'Erro interno no servidor', request_id: }, 500)
    end

    add_swagger_documentation(
      mount_path: '/swagger_doc',
      hide_documentation_path: true,
      format: :json,
      base_path: '/',
      info: {
        title: ENV.fetch('APP_NAME', 'robotrack'),
        description: "API do #{ENV.fetch('APP_NAME', 'robotrack')}."
      },
      security_definitions: {
        Bearer: {
          type: 'apiKey',
          name: 'Authorization',
          in: 'header',
          description: 'Token de autenticação no formato: Bearer {token}'
        }
      },
      security: [{ Bearer: [] }]
    )
  end
end
