# frozen_string_literal: true

module Api
  module V1
    # Gate de autorização do Grape (authorization-policies 2.1 / D3.4).
    #
    # Chamado pelo `before` de `Api::Root` DEPOIS da autenticação e da resolução
    # de tenant, ANTES de qualquer service. Lê a declaração da rota corrente:
    #
    #   route_setting :policy, policy: 'ProjectPolicy', action: :update
    #     — rota de DOMÍNIO: avalia a matriz §4.1 com o Context do request.
    #   route_setting :policy, access: :authenticated
    #     — rota autenticada SEM tenant (índice de workspaces, aceite por token,
    #       superfície global OG do template): a autenticação já aconteceu; a
    #       autorização fina permanece declarada no endpoint/service (decisão de
    #       execução 2 do EXECUCAO.md).
    #
    # Rota sem declaração NÃO responde 200 em ambiente algum: levanta
    # `Authorization::UndeclaredRouteError` (o rescue_from de Api::Root re-levanta
    # em development/test e responde 500 em produção — fail-closed).
    module AuthorizationHelpers
      def authorize_route!
        declaration = env[Grape::Env::API_ENDPOINT].route_setting(:policy)

        if declaration.nil?
          raise ::Authorization::UndeclaredRouteError,
                "#{request.request_method} #{request.path} sem route_setting :policy"
        end

        return if declaration[:access] == :authenticated

        policy = declaration.fetch(:policy)
        policy = policy.constantize if policy.is_a?(String)

        context = ::Authorization::Context.new(
          user: @current_user,
          workspace: ::Workspace.find_by(id: @current_workspace_id)
        )
        env['api.authorization_context'] = context

        # realtime-collaboration 3.4 — o autor da mutação para o envelope do
        # publisher (a Person do usuário no workspace corrente). Resolvido uma vez
        # por request de domínio, não por evento.
        ::Current.actor_person_id = context.person&.id

        policy.authorize!(context, declaration.fetch(:action))
      end
    end
  end
end
