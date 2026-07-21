# frozen_string_literal: true

module Api
  module V1
    # task-catalog 4.2–4.4 (§1.4 item 3, §3.9, D-TC-5, D-TC-7) — CRUD do catálogo
    # de tarefas-base, no escopo do workspace corrente.
    #
    # A compatibilidade legada `apps`/`appFilters` vive SÓ aqui, na fronteira: o
    # coerce converte para `app_filters` antes de tocar no model; `appFilters`
    # vence em conflito, com aviso estruturado. Nada abaixo deste endpoint conhece
    # o nome `apps` (D-TC-5). A normalização das sentinelas (`Misto / Geral`,
    # `Todas` → `[]`) e a validação de domínio moram no model (D-TC-2).
    #
    # O 404 é UNIFORME (D-TC-7): template de outro workspace é linha invisível
    # pela RLS, então `find_by` devolve nil e respondemos o MESMO corpo de um id
    # inexistente — 404, nunca 403, sem distinção que confirme existência.
    class TaskTemplates < Grape::API
      format :json
      helpers Api::V1::ControllerHelpers

      helpers do
        # D-TC-5: `appFilters` (novo) vence `apps` (legado). Devolve nil quando
        # nenhum dos dois veio (para o PATCH parcial não zerar o filtro à toa).
        def resolve_app_filters!(params)
          tem_novo   = params.key?(:appFilters) && !params[:appFilters].nil?
          tem_legado = params.key?(:apps) && !params[:apps].nil?

          if tem_novo && tem_legado
            Rails.logger.warn(
              {
                event: 'task_template_apps_conflict',
                message: 'apps e appFilters enviados juntos; appFilters vence',
                apps: params[:apps],
                app_filters: params[:appFilters]
              }.to_json
            )
          end

          return params[:appFilters] if tem_novo
          return params[:apps] if tem_legado

          nil
        end

        def present_template(template) = present(template, with: Api::Entities::TaskTemplate)

        # Mesmo corpo do rescue_from Authorization::NotFound — 404 byte-idêntico.
        def not_found! = error!({ error: 'not_found' }, 404)

        def unprocessable!(record)
          error!({ error: 'validation_error', details: record.errors.messages }, 422)
        end
      end

      resource :task_templates do
        route_setting :policy, policy: 'TaskTemplatePolicy', action: :index
        get do
          present ::TaskTemplate.ordered.to_a, with: Api::Entities::TaskTemplate
        end

        route_setting :policy, policy: 'TaskTemplatePolicy', action: :show
        params do
          requires :id, type: String
        end
        get ':id' do
          template = ::TaskTemplate.find_by(id: params[:id])
          not_found! if template.nil?
          present_template(template)
        end

        route_setting :policy, policy: 'TaskTemplatePolicy', action: :create
        params do
          optional :id, type: String
          requires :cat, type: String
          requires :desc, type: String
          optional :weight, type: BigDecimal
          optional :apps, type: Array[String]
          optional :appFilters, type: Array[String]
        end
        post do
          attrs = { cat: params[:cat], desc: params[:desc] }
          attrs[:id] = params[:id] if params[:id].present?
          attrs[:weight] = params[:weight] unless params[:weight].nil?
          filtros = resolve_app_filters!(params)
          attrs[:app_filters] = filtros unless filtros.nil?

          template = ::TaskTemplate.new(attrs)
          if template.save
            status 201
            present_template(template)
          else
            unprocessable!(template)
          end
        rescue ActiveRecord::RecordNotUnique
          # id já usado no workspace (§1.4/§3.9: cliente fornece o uuid) — 409 sem
          # criar segunda linha.
          error!({ error: 'conflict' }, 409)
        end

        route_setting :policy, policy: 'TaskTemplatePolicy', action: :update
        params do
          requires :id, type: String
          optional :cat, type: String
          optional :desc, type: String
          optional :weight, type: BigDecimal
          optional :apps, type: Array[String]
          optional :appFilters, type: Array[String]
        end
        patch ':id' do
          template = ::TaskTemplate.find_by(id: params[:id])
          not_found! if template.nil?

          template.cat = params[:cat] if params.key?(:cat)
          template.desc = params[:desc] if params.key?(:desc)
          template.weight = params[:weight] unless params[:weight].nil?
          filtros = resolve_app_filters!(params)
          template.app_filters = filtros unless filtros.nil?

          if template.save
            present_template(template)
          else
            unprocessable!(template)
          end
        rescue ActiveRecord::RecordNotUnique
          error!({ error: 'conflict' }, 409)
        end

        route_setting :policy, policy: 'TaskTemplatePolicy', action: :destroy
        params do
          requires :id, type: String
        end
        delete ':id' do
          template = ::TaskTemplate.find_by(id: params[:id])
          not_found! if template.nil?

          template.destroy!
          status 204
          body false
        end
      end
    end
  end
end
