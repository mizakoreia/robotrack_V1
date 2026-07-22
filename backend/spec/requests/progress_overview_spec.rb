# frozen_string_literal: true

require 'rails_helper'

# progress-rollup 3.2/3.5 (§3.2, D15, orçamento de query) — a Visão Geral leve:
# os dois envelopes rotulados no mesmo corpo (anel ponderado por projeto, hub de
# contagem crua do workspace) e o orçamento de query CONSTANTE no nº de projetos.
RSpec.describe 'Visão Geral (overview) do progresso', :tenancy, type: :request do
  let(:ana) { create(:user, name: 'Ana Dona') }
  let(:ws)  { make_workspace(owner: ana) }

  def headers = auth_headers(ana).merge('X-Workspace-Id' => ws.id)

  describe 'envelopes rotulados (D15)' do
    it 'expõe raw_completion (workspace) e weighted_progress por projeto, com métricas declaradas' do
      ids = in_workspace(ws) { seed_progress_divergence }
      get '/api/v1/projects/overview', headers: headers
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)

      # hub: contagem crua do workspace — 1 concluída de 5 → 20%
      expect(body['raw_completion']).to eq(
        'completed' => 1, 'total' => 5, 'percent' => 20,
        'metric' => 'raw_count', 'label' => 'Progresso físico (tarefas concluídas)'
      )

      # anel do projeto: ponderado — média das células (C1 = 58) → 58
      projeto = body['projects'].find { |p| p['id'] == ids.project }
      expect(projeto['weighted_progress']).to eq(
        'value' => 58, 'metric' => 'weighted', 'label' => 'Progresso ponderado'
      )

      # os dois números divergem de propósito e ambos são rotulados
      expect(body['raw_completion']['percent']).not_to eq(projeto['weighted_progress']['value'])
    end
  end

  describe 'orçamento de query (§3.2)' do
    it 'a query de dados da Visão Geral custa no máximo 2 SELECT' do
      in_workspace(ws) { 20.times { |i| Project.create!(name: "P#{i}", position: i) } }
      in_workspace(ws) do
        expect { Progress::OverviewQuery.call(workspace_id: ws.id) }.to issue_at_most(2).queries
      end
    end

    it '20 projetos custam o MESMO número de queries que 1 (sem N+1)' do
      def contar(headers)
        n = 0
        sub = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, p|
          n += 1 if p[:sql] =~ /\A\s*SELECT/i && p[:name] !~ /SCHEMA/i
        end
        get '/api/v1/projects/overview', headers: headers
        ActiveSupport::Notifications.unsubscribe(sub)
        n
      end

      in_workspace(ws) { Project.create!(name: 'só um', position: 0) }
      um = contar(headers)
      in_workspace(ws) { 19.times { |i| Project.create!(name: "mais#{i}", position: i + 1) } }
      vinte = contar(headers)

      expect(vinte).to eq(um) # constante no nº de projetos
    end
  end
end
