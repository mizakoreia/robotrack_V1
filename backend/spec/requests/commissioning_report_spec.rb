# frozen_string_literal: true

require 'rails_helper'

# commissioning-report 1.2–1.5 (§3.8, §4.1, D-R1) — o contrato e a autorização do
# endpoint do Protocolo: escopo válido/inválido, autorização por membership,
# isolamento cross-tenant, e o orçamento de ≤5 queries constantes em N.
RSpec.describe 'Protocolo de Comissionamento — GET /api/v1/commissioning_report', :tenancy, type: :request do
  let(:owner) { create(:user, name: 'Ana Dona') }
  let(:ws)    { make_workspace(owner: owner) }
  let(:owner_person) { in_workspace(ws) { Person.create!(name: 'Ana', user_id: owner.id) } }

  def headers(user = owner) = auth_headers(user).merge('X-Workspace-Id' => ws.id)

  # 1 projeto → 1 célula → 1 robô → N tarefas. Devolve o projeto.
  def seed_project(name: 'Linha A', tasks: 1, pos: 0)
    in_workspace(ws) do
      p = Project.create!(name: name, position: pos, progress_cache: 50)
      c = Cell.create!(project_id: p.id, name: 'C', position: 0, progress_cache: 50)
      r = Robot.create!(cell_id: c.id, name: 'R', application: 'Solda Ponto', position: 0, progress_cache: 50)
      tasks.times { |i| create_task(r, desc: "T#{i}", position: i, status: 'Em Andamento', progress: 50) }
      p
    end
  end

  describe 'contrato do payload = fixture congelada (1.1)' do
    it 'o payload real tem exatamente as chaves de topo da fixture' do
      owner_person
      seed_project(tasks: 1)
      get '/api/v1/commissioning_report?scope=all', headers: headers
      expect(response).to have_http_status(:ok)

      fixture = JSON.parse(File.read(Rails.root.join('spec/fixtures/reports/commissioning_report.json')))
      live = JSON.parse(response.body)
      expect(live.keys.sort).to eq(fixture.keys.sort)
      # e as subchaves críticas do carimbo/metadados/distribuição batem em forma
      expect(live['stamp'].keys.sort).to eq(fixture['stamp'].keys.sort)
      expect(live['metadata'].keys.sort).to eq(fixture['metadata'].keys.sort)
      expect(live['status_distribution'].first.keys.sort).to eq(fixture['status_distribution'].first.keys.sort)
    end
  end

  describe 'escopo (1.2)' do
    it 'scope inválido (cell) → 400' do
      owner_person
      get '/api/v1/commissioning_report?scope=cell', headers: headers
      expect(response).to have_http_status(:bad_request)
    end

    it 'scope=all → 200 com o documento (cabeçalho, carimbo, metadados, distribuição)' do
      owner_person
      seed_project(tasks: 2)
      get '/api/v1/commissioning_report?scope=all', headers: headers
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['header']['title']).to eq('PROTOCOLO DE COMISSIONAMENTO')
      expect(body['stamp']).to include('percent', 'label')
      expect(body['document_id']).to match(/\ART-\d{8}-\d{4}\z/)
      expect(body['status_distribution'].size).to eq(4)
      expect(body['metadata']['counts']).to eq('projects' => 1, 'cells' => 1, 'robots' => 1, 'tasks' => 2)
    end

    it 'scope=project conta apenas o escopo emitido' do
      owner_person
      alvo = seed_project(name: 'Linha B', tasks: 3, pos: 0)
      seed_project(name: 'Linha C', tasks: 5, pos: 1) # fora do escopo
      get "/api/v1/commissioning_report?scope=project&project_id=#{alvo.id}", headers: headers
      expect(response).to have_http_status(:ok)
      counts = JSON.parse(response.body)['metadata']['counts']
      expect(counts).to eq('projects' => 1, 'cells' => 1, 'robots' => 1, 'tasks' => 3)
    end
  end

  describe 'autorização e isolamento (1.5, §4.1)' do
    it 'membro view emite (200)' do
      vera = create(:user, name: 'Vera View')
      add_member(ws, vera, 'view')
      seed_project(tasks: 1)
      get '/api/v1/commissioning_report?scope=all', headers: auth_headers(vera).merge('X-Workspace-Id' => ws.id)
      expect(response).to have_http_status(:ok)
    end

    it 'usuário sem associação → 403, sem vazar nome/contagens' do
      # a resolução de tenant (X-Workspace-Id) barra o não-membro com
      # `workspace_access_denied` ANTES do gate/endpoint — 403 leak-free (o corpo
      # não traz nome nem contagens). O 404 da spec para não-membro não é
      # alcançável neste app (o middleware responde antes); o isolamento (não
      # vazar) está garantido. O 404 real é o do projeto cross-tenant (abaixo).
      seed_project(name: 'SEGREDO', tasks: 1)
      estranho = create(:user, name: 'Estranho')
      get '/api/v1/commissioning_report?scope=all', headers: auth_headers(estranho).merge('X-Workspace-Id' => ws.id)
      expect(response).to have_http_status(:forbidden)
      expect(response.body).not_to include('SEGREDO')
    end

    it 'scope=project sobre projeto de OUTRO workspace → 404 (RLS)' do
      owner_person
      bob = create(:user, name: 'Bob')
      w2 = make_workspace(owner: bob)
      w2_project = in_workspace(w2) { Project.create!(name: 'PROJETO W2', position: 0, progress_cache: 0).id }
      get "/api/v1/commissioning_report?scope=project&project_id=#{w2_project}", headers: headers
      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include('W2')
    end

    it 'sem token → 401 (inclusive com X-Skip-Auth: 1)' do
      get '/api/v1/commissioning_report?scope=all', headers: { 'X-Workspace-Id' => ws.id, 'X-Skip-Auth' => '1' }
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'orçamento de queries CONSTANTE em N (1.4, D-R8)' do
    def count_queries
      n = 0
      sub = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, p|
        sql = p[:sql]
        next if p[:name] == 'SCHEMA' || sql =~ /\A\s*(BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE|SET|SHOW)/i
        n += 1
      end
      yield
      ActiveSupport::Notifications.unsubscribe(sub)
      n
    end

    it '8 projetos custam o MESMO número de queries que 1 (≤5, constante em N)' do
      owner_person
      q1 = nil
      q8 = nil
      seed_project(name: 'P0', tasks: 2, pos: 0)
      # o Context é montado pelo GATE antes do service (não conta no orçamento do
      # service) — construo FORA do count_queries.
      in_workspace(ws) do
        c = ctx
        q1 = count_queries { Reports::CommissioningReportService.new(context: c).call(scope: 'all') }
      end
      7.times { |i| seed_project(name: "PX#{i}", tasks: 2, pos: i + 1) }
      in_workspace(ws) do
        c = ctx
        q8 = count_queries { Reports::CommissioningReportService.new(context: c).call(scope: 'all') }
      end
      expect(q8).to eq(q1)
      expect(q8).to be <= 5
    end

    def ctx = Authorization::Context.new(user: owner, workspace: Workspace.find(ws.id))
  end
end
