# frozen_string_literal: true

module Api
  module V1
    class Base < Grape::API
      format :json
      version 'v1', using: :path
      prefix :api

      helpers Api::V1::ControllerHelpers

      namespace :users do
        mount Api::V1::Users
      end

      namespace :uploads do
        mount Api::V1::Uploads
      end

      mount Api::V1::Workspaces

      # Hierarquia de comissionamento (commissioning-hierarchy 4.5)
      mount Api::V1::Projects
      mount Api::V1::Cells
      mount Api::V1::Robots

      # Busca da hierarquia (hierarchy-screens 3.1)
      mount Api::V1::Search

      # Catálogo de tarefas-base e metadados (task-catalog 4.2–4.5)
      mount Api::V1::TaskTemplates
      mount Api::V1::Meta

      # Tarefas do robô (robot-tasks 3.1–3.6)
      mount Api::V1::Tasks

      # Minhas Tarefas — a lista pessoal do viewer (my-tasks-view 3.3)
      mount Api::V1::MyTasks

      # Protocolo de Comissionamento (commissioning-report 1.3)
      mount Api::V1::Reports

      # Log de auditoria — leitura (audit-log 5.2)
      mount Api::V1::AuditLogs

      # Pessoas do workspace — painel de Equipe (workspace-settings 2.1)
      mount Api::V1::People

      # Recálculo manual do progresso (progress-rollup 4.5)
      mount Api::V1::ProgressEndpoint

      # Criação de robôs em lote (robot-tasks 5.5)
      mount Api::V1::RobotBatches

      mount Api::V1::Invitations
      mount Api::V1::InvitationTokens

      mount Api::V1::Memberships

      mount Api::V1::Countries

      mount Api::V1::Downloads

      # Sonda de tenancy: rota de domínio existente só em teste, para exercitar a
      # fiação de contexto e a varredura de rotas (workspace-tenancy 4.x).
      mount Api::V1::TenancyProbe if Rails.env.test?

      # Tratamento de erro é único e vive em Api::Root.
    end
  end
end
