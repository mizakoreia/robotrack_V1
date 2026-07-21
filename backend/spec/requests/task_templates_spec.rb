# frozen_string_literal: true

require 'rails_helper'

# task-catalog 4.6 (§1.4, §3.9, §4.1, D-TC-5, D-TC-7) — a suíte de request do
# catálogo: leitura tolerante e ordenada, coerce `apps`/`appFilters`,
# normalização das sentinelas, 404 byte-idêntico cross-tenant, e a autorização
# batendo direto no endpoint (bloqueio de UI não conta).
RSpec.describe 'API do catálogo de tarefas-base', :tenancy, type: :request do
  let(:ana)   { create(:user, name: 'Ana Dona') }
  let(:ws)    { make_workspace(owner: ana) }
  let(:bruno) { create(:user, name: 'Bruno Edit') }
  let(:clara) { create(:user, name: 'Clara View') }
  let(:diego) { create(:user, name: 'Diego De B') }
  let(:ws_b)  { make_workspace(owner: diego) }

  def headers(user, workspace = ws)
    auth_headers(user).merge('X-Workspace-Id' => workspace.id)
  end

  def seed_catalog(workspace)
    in_workspace(workspace) do
      Workspaces::SeedDefaultTaskTemplatesService.new(workspace_id: workspace.id).call
    end
  end

  def template_id(workspace, desc)
    in_workspace(workspace) { TaskTemplate.find_by!(desc: desc).id }
  end

  before do
    add_member(ws, bruno, 'edit')
    add_member(ws, clara, 'view')
    seed_catalog(ws)
  end

  describe 'leitura' do
    it 'view lê os 31 templates ordenados A..I, com appFilters e sem apps' do
      get '/api/v1/task_templates', headers: headers(clara)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body.size).to eq(31)
      expect(body.map { |t| t['cat'] }.uniq).to eq(
        [
          'A. Hardware', 'B. Rede', 'C. Segurança', 'D. Processo', 'E. Trajetórias',
          'F. Interlocks', 'G. Tryout', 'H. Otimização', 'I. Aceitação'
        ]
      )
      expect(body.first).to have_key('appFilters')
      expect(body.first).not_to have_key('apps')
      cola = body.find { |t| t['desc'] == 'Calibração de Cola' }
      expect(cola['appFilters']).to eq(['Sealing'])
      expect(cola['weight']).to eq(1)
    end

    it 'show devolve o template; id de outro workspace é 404 byte-idêntico a id inexistente' do
      id = template_id(ws, 'TCP Check')

      get "/api/v1/task_templates/#{id}", headers: headers(ana)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['desc']).to eq('TCP Check')

      # Diego (dono de WS-B) endereça um template de WS-A → 404 = id inexistente.
      get "/api/v1/task_templates/#{id}", headers: headers(diego, ws_b)
      corpo_cross = response.body
      status_cross = response.status
      get "/api/v1/task_templates/#{SecureRandom.uuid}", headers: headers(diego, ws_b)

      expect(status_cross).to eq(404)
      expect(response.status).to eq(404)
      expect(corpo_cross).to eq(response.body)
    end
  end

  describe 'criação' do
    it 'edit cria com weight 1 e appFilters [] por padrão (201)' do
      post '/api/v1/task_templates',
           params: { cat: 'J. Elétrica', desc: 'Check de aterramento' }, headers: headers(bruno)

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body['weight']).to eq(1)
      expect(body['appFilters']).to eq([])
    end

    it 'aceita apps (legado) e responde appFilters, nunca apps' do
      post '/api/v1/task_templates',
           params: { cat: 'D. Processo', desc: 'Check de cola', apps: ['Sealing'] }, headers: headers(bruno)

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body['appFilters']).to eq(['Sealing'])
      expect(body).not_to have_key('apps')
    end

    it 'appFilters vence apps e registra warning estruturado' do
      allow(Rails.logger).to receive(:warn)

      post '/api/v1/task_templates',
           params: { cat: 'D. Processo', desc: 'Conflito', apps: ['Handling'], appFilters: ['Sealing'] },
           headers: headers(bruno)

      expect(JSON.parse(response.body)['appFilters']).to eq(['Sealing'])
      expect(Rails.logger).to have_received(:warn).with(/task_template_apps_conflict/)
    end

    it 'desc em branco: 422 e o catálogo continua com 31' do
      post '/api/v1/task_templates',
           params: { cat: 'A. Hardware', desc: '   ' }, headers: headers(bruno)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(in_workspace(ws) { TaskTemplate.count }).to eq(31)
    end

    it 'cliente fornece o uuid; segundo POST com o mesmo id é 409 sem segunda linha' do
      id = SecureRandom.uuid
      post '/api/v1/task_templates',
           params: { id: id, cat: 'A. Hardware', desc: 'Com id fixo' }, headers: headers(bruno)
      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)['id']).to eq(id)

      post '/api/v1/task_templates',
           params: { id: id, cat: 'A. Hardware', desc: 'Outra desc' }, headers: headers(bruno)
      expect(response).to have_http_status(:conflict)
      expect(in_workspace(ws) { TaskTemplate.where(id: id).count }).to eq(1)
    end
  end

  describe 'edição de filtro (normalização §3.9)' do
    it 'Misto / Geral limpa o filtro e o template passa a valer para Solda MIG' do
      id = template_id(ws, 'Calibração de Cola')

      patch "/api/v1/task_templates/#{id}", params: { appFilters: ['Misto / Geral'] }, headers: headers(bruno)

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['appFilters']).to eq([])
      tpl = in_workspace(ws) { TaskTemplate.find(id) }
      expect(TaskTemplates::ApplicabilityFilter.applicable?(tpl, 'Solda MIG')).to be(true)
    end

    it 'a sentinela Todas também limpa (não é gravada por escrita de API)' do
      id = template_id(ws, 'Check sinais de Gripper')
      patch "/api/v1/task_templates/#{id}", params: { appFilters: ['Todas'] }, headers: headers(bruno)
      expect(JSON.parse(response.body)['appFilters']).to eq([])
    end

    it 'duplicatas são removidas preservando a ordem' do
      id = template_id(ws, 'Check sinais de Gripper')
      patch "/api/v1/task_templates/#{id}",
            params: { appFilters: ['Handling', 'Solda Ponto', 'Handling'] }, headers: headers(bruno)
      expect(JSON.parse(response.body)['appFilters']).to eq(['Handling', 'Solda Ponto'])
    end

    it 'filtro inválido: 422 e o app_filters anterior permanece no banco' do
      id = template_id(ws, 'Calibração de Cola')
      patch "/api/v1/task_templates/#{id}", params: { appFilters: ['Solda a Laser'] }, headers: headers(bruno)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(in_workspace(ws) { TaskTemplate.find(id).app_filters }).to eq(['Sealing'])
    end
  end

  describe 'exclusão' do
    it 'edit exclui: catálogo 31 → 30' do
      id = template_id(ws, 'Speed up')
      delete "/api/v1/task_templates/#{id}", headers: headers(bruno)

      expect(response).to have_http_status(:no_content)
      expect(in_workspace(ws) { TaskTemplate.count }).to eq(30)
    end
  end

  describe 'autorização — view não escreve (bate no endpoint, não na UI)' do
    it 'view não cria: 403 e catálogo continua 31' do
      post '/api/v1/task_templates',
           params: { cat: 'A. Hardware', desc: 'Check extra' }, headers: headers(clara)

      expect(response).to have_http_status(:forbidden)
      expect(in_workspace(ws) { TaskTemplate.count }).to eq(31)
    end

    it 'view não edita nem exclui: 403, weight de TCP Check continua 1 e o template persiste' do
      id = template_id(ws, 'TCP Check')

      patch "/api/v1/task_templates/#{id}", params: { weight: 5 }, headers: headers(clara)
      expect(response).to have_http_status(:forbidden)
      expect(in_workspace(ws) { TaskTemplate.find(id).weight }).to eq(1)

      delete "/api/v1/task_templates/#{id}", headers: headers(clara)
      expect(response).to have_http_status(:forbidden)
      expect(in_workspace(ws) { TaskTemplate.exists?(id) }).to be(true)
    end
  end

  describe 'metadados (§1.2)' do
    it 'devolve os 6 valores na ordem da §1.2, sem "Todas"' do
      get '/api/v1/meta/robot_applications', headers: auth_headers(ana)

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq(
        ['Misto / Geral', 'Solda Ponto', 'Solda MIG', 'Handling', 'Sealing', 'Outros']
      )
    end

    it 'exige autenticação (401 sem token)' do
      get '/api/v1/meta/robot_applications'
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
