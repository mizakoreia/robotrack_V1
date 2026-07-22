# frozen_string_literal: true

module Api
  module V1
    # audit-log 5.2 (§2.8, Decisão 9) — a leitura do log de auditoria. Rota de
    # DOMÍNIO: exige `X-Workspace-Id`; o gate resolve o tenant e avalia
    # `AuditLogPolicy#index?` (`read_workspace` — qualquer membro, inclusive `view`)
    # ANTES daqui. Isolamento por RLS.
    #
    # ÚNICA operação: `GET`. Não há POST/PUT/PATCH/DELETE — o único produtor é o
    # service interno `AuditLog::RecordService` (§4.1 inv. 1: nem o dono tem rota de
    # escrita/exclusão). Teto RÍGIDO de 200 no servidor (Decisão 9): sem `offset`,
    # sem paginação; `?limit` é clampeado. Ordem `ts DESC` (mais recente primeiro).
    class AuditLogs < Grape::API
      format :json
      helpers Api::V1::ControllerHelpers

      MAX_LIMIT = 200

      resource :audit_logs do
        route_setting :policy, policy: 'AuditLogPolicy', action: :index
        params do
          optional :limit, type: Integer, default: MAX_LIMIT
        end
        get do
          limit = params[:limit].to_i
          limit = MAX_LIMIT if limit <= 0 || limit > MAX_LIMIT

          rows = ::AuditLog.order(ts: :desc).limit(limit)
          present rows, with: Api::Entities::AuditLog
        end
      end
    end
  end
end
