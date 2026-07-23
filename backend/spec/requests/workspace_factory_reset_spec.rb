# frozen_string_literal: true

require 'rails_helper'

# workspace-settings G5 (§3.11, D12, D-RESET, D-RESET-GATE, D-RESET-ROLLBACK) — o
# reset de fábrica. A prova central de D12: o reset ARQUIVA a hierarquia (via
# Hierarchy::SoftDeleteService — DELETE era impossível, os avanços são imutáveis),
# preserva audit_logs/people/memberships/workspaces/backups, re-semeia o catálogo,
# revoga convites pendentes e grava UMA entrada de auditoria NA MESMA transação.
RSpec.describe 'workspace-settings — POST /api/v1/workspace/factory_reset', :tenancy, type: :request do
  let(:owner) { create(:user, name: 'Ana Dona') }
  let(:ws)    { make_workspace(owner: owner, name: 'Fábrica Alfa') }

  def headers(user = owner) = auth_headers(user).merge('X-Workspace-Id' => ws.id)

  before { allow(::Workspace::FactoryResetService).to receive(:feature_enabled?).and_return(true) }

  # Semeia o estado pré-reset: 2 projetos (1 com árvore completa + avanço), 1
  # template custom, 1 convite pendente + 1 consumido, 1 entrada de auditoria
  # anterior, e o backup completed. Devolve os ids que as provas comparam.
  def seed
    in_workspace(ws) do
      person = Person.create!(name: 'Ana', user_id: owner.id)
      p1 = Project.create!(name: 'Linha 1', position: 0)
      Project.create!(name: 'Linha 2', position: 1)
      c = Cell.create!(project_id: p1.id, name: 'C', position: 0)
      r = Robot.create!(cell_id: c.id, name: 'R', position: 0)
      t = create_task(r, desc: 'T', position: 0, status: 'Em Andamento', progress: 45)
      TaskAdvance.create!(
        task_id: t.id, workspace_id: ws.id, by: person.id, author_name_snapshot: 'Ana',
        from_progress: 0, to_progress: 45, comment: 'início', recorded_at: 1.hour.ago
      )
      TaskTemplate.create!(cat: 'A. Hardware', desc: 'Template custom fora do padrão')
      Invitation.create!(email: 'pendente@ex.com', role: 'view', created_by_person: person)
      usado = Invitation.create!(email: 'usada@ex.com', role: 'edit', created_by_person: person,
                                 used_at: 1.day.ago, used_by_user: owner)
      AuditLog::RecordService.record!(
        workspace: Workspace.find(ws.id), event: :task_completed, by: person,
        payload: { robot_name: 'R', task_desc: 'Antiga', assignee_names: ['Ana'] }
      )
      backup = WorkspaceBackup.create!(status: 'completed')
      { person: person.id, task: t.id, backup: backup.id, invitation_used: usado.id }
    end
  end

  def reset!(ids, phrase: 'Fábrica Alfa')
    post '/api/v1/workspace/factory_reset',
         params: { confirmation_phrase: phrase, backup_id: ids[:backup] },
         headers: headers
  end

  describe 'caminho feliz (D-RESET reconciliado: arquiva, não apaga)' do
    it 'arquiva a hierarquia, preserva a trilha, re-semeia o catálogo e audita na transação' do
      ids = seed
      reset!(ids)

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['projects_count']).to eq(2)

      in_workspace(ws) do
        # hierarquia SOME da leitura, mas as linhas EXISTEM arquivadas
        expect(Project.count).to eq(0)
        expect(Project.unscoped.where.not(deleted_at: nil).count).to eq(2)
        expect(Robot.count).to eq(0)
        expect(Task.count).to eq(0)
        # a trilha imutável está INTACTA (D-IMUT — o motivo de arquivar)
        expect(TaskAdvance.where(task_id: ids[:task]).count).to eq(1)
        # catálogo voltou ao padrão de fábrica: 31, sem o custom
        expect(TaskTemplate.count).to eq(31)
        expect(TaskTemplate.where('lower(btrim("desc")) = ?', 'template custom fora do padrão')).to be_empty
        # convite pendente revogado (DELETE — o caminho abençoado); o consumido fica
        expect(Invitation.pending.count).to eq(0)
        expect(Invitation.where(id: ids[:invitation_used])).to be_present
        # pessoas/memberships/workspace/backup preservados
        expect(Person.where(id: ids[:person])).to be_present
        expect(Membership.where(workspace_id: ws.id).count).to eq(0) # dono não é membership
        expect(Workspace.find(ws.id).name).to eq('Fábrica Alfa')
        expect(WorkspaceBackup.find(ids[:backup]).consumed_at).to be_present
        # auditoria: a anterior sobrevive + a nova do reset com contagem e autor
        logs = AuditLog.order(ts: :desc).to_a
        expect(logs.size).to eq(2)
        expect(logs.first.msg).to include('Ana', 'reset de fábrica', '2')
        expect(logs.last.msg).to include('Antiga')
      end
    end

    it 'emite alerta operacional pós-commit com workspace, autor e contagens (5.10/§3.11)' do
      ids = seed
      allow(Ops::AlertService).to receive(:raise_alert).and_call_original

      reset!(ids)

      expect(response).to have_http_status(:ok)
      expect(Ops::AlertService).to have_received(:raise_alert).with(
        hash_including(
          key: "workspace_reset:#{ws.id}",
          severity: :warning,
          message: a_string_including('Fábrica Alfa'),
          context: hash_including(
            workspace_id: ws.id, by_name: 'Ana',
            projects_archived: 2, templates_reseeded: 31
          )
        )
      )
    end

    it 'não emite DELETE/UPDATE contra audit_logs durante o reset (D12/5.6)' do
      ids = seed
      mutacoes = []
      capturador = lambda do |_n, _s, _f, _id, payload|
        sql = payload[:sql].to_s
        mutacoes << sql if sql.match?(/\b(DELETE\s+FROM|UPDATE)\s+"?audit_logs/i)
      end
      ActiveSupport::Notifications.subscribed(capturador, 'sql.active_record') { reset!(ids) }

      expect(response).to have_http_status(:ok)
      expect(mutacoes).to be_empty, "mutação proibida em audit_logs:\n#{mutacoes.join("\n")}"
    end
  end

  describe 'gates (D-RESET-GATE)' do
    it 'frase com caixa divergente → 422, nada arquivado, nenhuma auditoria' do
      ids = seed
      reset!(ids, phrase: 'fábrica alfa')

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)['error']).to eq('reset_phrase_mismatch')
      in_workspace(ws) do
        expect(Project.count).to eq(2)
        expect(AuditLog.count).to eq(1) # só a entrada anterior
        expect(WorkspaceBackup.find(ids[:backup]).consumed_at).to be_nil
      end
    end

    it 'backup velho (>15 min) → 422 sem executar' do
      ids = seed
      in_workspace(ws) { WorkspaceBackup.find(ids[:backup]).update_column(:created_at, 16.minutes.ago) }
      reset!(ids)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)['error']).to eq('reset_backup_invalid')
      in_workspace(ws) { expect(Project.count).to eq(2) }
    end

    it 'backup pending (não completed) → 422' do
      ids = seed
      in_workspace(ws) { WorkspaceBackup.find(ids[:backup]).update_column(:status, 'pending') }
      reset!(ids)
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'duplo clique: o segundo reset acha o backup consumido → 422, UMA entrada de auditoria' do
      ids = seed
      reset!(ids)
      expect(response).to have_http_status(:ok)
      reset!(ids)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)['error']).to eq('reset_backup_invalid')
      in_workspace(ws) do
        expect(AuditLog.where(event_type: 'workspace_reset').count).to eq(1)
      end
    end
  end

  describe 'autorização e flag' do
    it 'edit → 403 mesmo com frase e backup corretos (destroy_workspace é do dono)' do
      ids = seed
      vera = create(:user, name: 'Vera Edit'); add_member(ws, vera, 'edit')
      post '/api/v1/workspace/factory_reset',
           params: { confirmation_phrase: 'Fábrica Alfa', backup_id: ids[:backup] },
           headers: auth_headers(vera).merge('X-Workspace-Id' => ws.id)

      expect(response).to have_http_status(:forbidden)
      in_workspace(ws) { expect(Project.count).to eq(2) }
    end

    it 'FEATURE_FACTORY_RESET desligada → 404 e nada executa' do
      ids = seed
      allow(::Workspace::FactoryResetService).to receive(:feature_enabled?).and_return(false)
      reset!(ids)

      expect(response).to have_http_status(:not_found)
      in_workspace(ws) { expect(Project.count).to eq(2) }
    end
  end

  describe 'rollback (D-RESET-ROLLBACK)' do
    it 'falha na escrita da auditoria desfaz TUDO: hierarquia viva, backup não consumido, zero log de reset' do
      ids = seed
      allow(::AuditLog::RecordService).to receive(:record!).and_raise(RuntimeError, 'injetada')
      reset!(ids)

      expect(response.status).to be >= 500
      in_workspace(ws) do
        expect(Project.count).to eq(2)
        expect(Task.count).to eq(1)
        expect(TaskTemplate.where('lower(btrim("desc")) = ?', 'template custom fora do padrão')).to be_present
        expect(Invitation.pending.count).to eq(1)
        expect(AuditLog.where(event_type: 'workspace_reset').count).to eq(0)
        expect(WorkspaceBackup.find(ids[:backup]).consumed_at).to be_nil
      end
    end
  end
end
