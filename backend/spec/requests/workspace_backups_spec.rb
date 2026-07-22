# frozen_string_literal: true

require 'rails_helper'

# workspace-settings 4.3/4.4 (§3.11, D-EXP-ROLE) — o endpoint de backup: owner emite
# o `RoboTrack_Database.json` (Content-Disposition + X-Backup-Id) e registra a linha
# `completed`; edit/view recebem 403 sem criar linha; acima do teto vira job (202).
RSpec.describe 'workspace-settings — POST /api/v1/workspace/backups', :tenancy, type: :request do
  let(:owner) { create(:user, name: 'Ana Dona') }
  let(:ws)    { make_workspace(owner: owner) }

  def headers(user = owner) = auth_headers(user).merge('X-Workspace-Id' => ws.id)

  def seed
    in_workspace(ws) do
      Person.create!(name: 'Ana Lima')
      p = Project.create!(name: 'Linha A', position: 0)
      c = Cell.create!(project_id: p.id, name: 'C', position: 0)
      r = Robot.create!(cell_id: c.id, name: 'R', application: 'Sealing', position: 0)
      create_task(r, desc: 'T', position: 0, status: 'Pendente', progress: 0)
    end
  end

  describe 'owner emite (D-EXP-ROLE)' do
    it '200 com o arquivo (Content-Disposition + X-Backup-Id) e cria a linha completed' do
      seed
      expect { post '/api/v1/workspace/backups', headers: headers }
        .to change { in_workspace(ws) { WorkspaceBackup.count } }.by(1)
      expect(response).to have_http_status(:ok)
      expect(response.headers['Content-Disposition']).to include('RoboTrack_Database.json')
      backup_id = response.headers['X-Backup-Id']
      expect(backup_id).to be_present
      body = JSON.parse(response.body)
      expect(body['_rt']['schemaVersion']).to eq(2)
      backup = in_workspace(ws) { WorkspaceBackup.find(backup_id) }
      expect(backup.status).to eq('completed')
      expect(backup.checksum).to eq(body['_rt']['checksum'])
    end
  end

  describe 'não-donos são negados' do
    it 'edit → 403, nenhuma linha criada' do
      vera = create(:user, name: 'Vera Edit'); add_member(ws, vera, 'edit')
      seed
      expect { post '/api/v1/workspace/backups', headers: headers(vera) }
        .not_to change { in_workspace(ws) { WorkspaceBackup.count } }
      expect(response).to have_http_status(:forbidden)
    end

    it 'view → 403' do
      vera = create(:user, name: 'Vera View'); add_member(ws, vera, 'view')
      post '/api/v1/workspace/backups', headers: headers(vera)
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'acima do teto → job (4.4)' do
    around do |ex|
      old = ActiveJob::Base.queue_adapter
      ActiveJob::Base.queue_adapter = :test
      ex.run
      ActiveJob::Base.queue_adapter = old
    end

    it 'responde 202 com backup_id/status e enfileira o job (linha fica pending)' do
      stub_const('Api::V1::WorkspaceBackups::MAX_SYNC_TASKS', 0)
      seed
      expect { post '/api/v1/workspace/backups', headers: headers }
        .to have_enqueued_job(Workspace::BackupExportJob)
      expect(response).to have_http_status(:accepted)
      body = JSON.parse(response.body)
      expect(body['status']).to eq('pending')
      expect(in_workspace(ws) { WorkspaceBackup.find(body['backup_id']).status }).to eq('pending')
    end
  end
end
