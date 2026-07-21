# frozen_string_literal: true

require 'rails_helper'

# authorization-policies 5.5 — a matriz §4.1 exercitada papel × ação, com
# maioria de casos NEGATIVOS. Duas camadas (EXECUCAO, decisão 6):
#
#   1. As 24 células (3 papéis × 8 actions) contra PermissionMatrix — sempre.
#   2. Por HTTP, as linhas que JÁ têm endpoint (leitura de equipe e gestão de
#      membros/convites). As linhas cujas rotas pertencem a capacidades
#      futuras ficam `pending` nomeando quem as trará.
RSpec.describe 'Conformidade papel × ação com a §4.1', :tenancy, type: :request do
  describe 'camada 1 — as 24 células da matriz' do
    ESPERADO = {
      read_workspace:         { owner: true,  edit: true,  view: true  },
      manage_commissioning:   { owner: true,  edit: true,  view: false },
      record_progress:        { owner: true,  edit: true,  view: false },
      manage_catalog:         { owner: true,  edit: true,  view: false },
      create_log:             { owner: true,  edit: true,  view: false },
      mark_notification_read: { owner: true,  edit: true,  view: true  },
      manage_membership:      { owner: true,  edit: false, view: false },
      destroy_workspace:      { owner: true,  edit: false, view: false }
    }.freeze

    ESPERADO.each do |action, papeis|
      papeis.each do |papel, permitido|
        it "#{action} × #{papel} = #{permitido}" do
          expect(PermissionMatrix.allows?(action, papel)).to be(permitido)
        end
      end
    end

    it 'a tabela deste spec cobre exatamente as actions da matriz' do
      expect(ESPERADO.keys).to eq(PermissionMatrix::ACTIONS.keys)
    end
  end

  describe 'camada 2 — por HTTP, na superfície existente' do
    let(:ana)   { create(:user, name: 'Ana Owner') }
    let(:ws)    { make_workspace(owner: ana) }
    let(:bruno) { create(:user, name: 'Bruno Edit') }
    let(:clara) { create(:user, name: 'Clara View') }

    before do
      add_member(ws, bruno, 'edit')
      add_member(ws, clara, 'view')
    end

    def headers(user) = auth_headers(user).merge('X-Workspace-Id' => ws.id)

    it 'read_workspace: os TRÊS papéis leem a equipe' do
      [ana, bruno, clara].each do |user|
        get '/api/v1/memberships', headers: headers(user)
        expect(response).to have_http_status(:ok), "#{user.name} deveria ler a equipe"
      end
    end

    it 'manage_membership: Bruno (edit) recebe 403 em criar convite, mudar papel e remover' do
      membership_clara = in_workspace(ws) { Membership.find_by(user_id: clara.id) }

      post '/api/v1/invitations', params: { email: 'x@ex.com', role: 'view' }, headers: headers(bruno)
      expect(response).to have_http_status(:forbidden)

      patch "/api/v1/memberships/#{membership_clara.id}", params: { role: 'edit' }, headers: headers(bruno)
      expect(response).to have_http_status(:forbidden)

      delete "/api/v1/memberships/#{membership_clara.id}", headers: headers(bruno)
      expect(response).to have_http_status(:forbidden)

      expect(in_workspace(ws) { Membership.find_by(user_id: clara.id).role }).to eq('view')
    end

    it 'manage_membership: Clara (view) também recebe 403' do
      post '/api/v1/invitations', params: { email: 'x@ex.com', role: 'view' }, headers: headers(clara)
      expect(response).to have_http_status(:forbidden)
    end

    it 'manage_membership: Ana (owner) executa' do
      post '/api/v1/invitations', params: { email: 'nova@ex.com', role: 'view' }, headers: headers(ana)
      expect(response).to have_http_status(:created)
    end

    it 'manage_commissioning por HTTP: Clara (view) não cria/edita/exclui; Bruno (edit) executa' do
      projeto = in_workspace(ws) { Project.create!(name: 'Linha HTTP') }
      celula  = in_workspace(ws) { Cell.create!(project_id: projeto.id, name: 'Célula HTTP') }
      robo    = in_workspace(ws) { Robot.create!(cell_id: celula.id, name: 'Robô HTTP') }

      post '/api/v1/projects', params: { name: 'De Clara' }, headers: headers(clara)
      expect(response).to have_http_status(:forbidden)
      patch "/api/v1/cells/#{celula.id}", params: { name: 'X', lock_version: 0 }, headers: headers(clara)
      expect(response).to have_http_status(:forbidden)
      delete "/api/v1/robots/#{robo.id}", headers: headers(clara)
      expect(response).to have_http_status(:forbidden)
      expect(in_workspace(ws) { Robot.count }).to eq(1)

      post '/api/v1/projects', params: { name: 'De Bruno' }, headers: headers(bruno)
      expect(response).to have_http_status(:created)
      patch "/api/v1/cells/#{celula.id}", params: { name: 'Renomeada', lock_version: 0 }, headers: headers(bruno)
      expect(response).to have_http_status(:ok)
      delete "/api/v1/robots/#{robo.id}", headers: headers(bruno)
      expect(response).to have_http_status(:no_content)
    end

    it 'manage_commissioning por HTTP para TAREFAS' do
      pending 'bloqueada por robot-tasks — os endpoints de tarefa não existem'
      raise 'implementar quando robot-tasks expuser as rotas'
    end

    it 'record_progress por HTTP (avanços, atribuição, reordenação)' do
      pending 'bloqueada por progress-advances — os endpoints de avanço não existem'
      raise 'implementar quando progress-advances expuser as rotas'
    end

    it 'manage_catalog por HTTP (tarefas-base e responsáveis)' do
      pending 'bloqueada por task-catalog — os endpoints de catálogo não existem'
      raise 'implementar quando task-catalog expuser as rotas'
    end

    it 'create_log e mark_notification_read por HTTP' do
      pending 'bloqueada por audit-log e in-app-notifications — os endpoints não existem'
      raise 'implementar quando as capacidades expuserem as rotas'
    end

    it 'destroy_workspace por HTTP (excluir workspace / factory reset)' do
      pending 'bloqueada por workspace-settings — DELETE de workspace e factory_reset não existem'
      raise 'implementar quando workspace-settings expuser as rotas'
    end
  end
end
