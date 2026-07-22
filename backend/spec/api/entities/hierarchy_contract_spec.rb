# frozen_string_literal: true

require 'rails_helper'

# hierarchy-screens 1.1 + 1.3 (D-A / D15) — o contrato das duas métricas, no nível
# da fixture e das entities. A parte de REQUEST (percorrer os 4 endpoints) mora nos
# specs de request de G2/G3, reusando o mesmo `ProgressKeyScanner`; aqui prova-se
# que (a) a fixture divergente produz de fato 40 ≠ 25 sob a fórmula JÁ ENTREGUE, e
# (b) as entities nunca emitem a chave proibida `progress`.
RSpec.describe 'Contrato das duas métricas (D15)' do
  describe 'fixture divergente sob a fórmula real', :tenancy do
    let(:dona) { create(:user, name: 'Ana Dona') }
    let(:ws)   { make_workspace(owner: dona) }

    it 'produz ponderado 40 (anel) e contagem crua 1/4 = 25% (hub) — divergentes' do
      ids = in_workspace(ws) { seed_divergent_progress }

      assert_divergent! # a própria fixture é inválida se os dois valores coincidirem

      weighted, raw = in_workspace(ws) do
        w = Robot.find(ids.robot).progress_cache
        r = ActiveRecord::Base.connection.select_one(
          ActiveRecord::Base.sanitize_sql_array(
            ["SELECT completed, total, percent FROM subtree_raw_completion " \
             "WHERE scope_type = 'robot' AND scope_id = ?", ids.robot]
          )
        )
        [w, r]
      end

      expect(weighted).to eq(HierarchyDivergentFixture::EXPECTED[:weighted]) # 40
      expect(raw.values_at('completed', 'total', 'percent')).to eq([1, 4, 25])
      expect(weighted).not_to eq(raw['percent']) # a prova: 40 ≠ 25
    end
  end

  describe 'entities não expõem a chave proibida `progress`' do
    # amostras no formato que os services de G2/G3 vão montar
    let(:project_card) { { id: 'p1', name: 'Linha 300', weighted_progress: 40, cells_count: 4 } }
    let(:cell_card)    { { id: 'c1', name: 'Célula 01', weighted_progress: 55, robots_count: 2 } }
    let(:robot_card)   { { id: 'r1', name: 'R01', weighted_progress: 40, application: 'Solda', tasks_count: 4 } }
    let(:hub) do
      { counts: { active_projects: 3, analyzed_robots: 12, completed_tasks: 1 },
        raw_completion: { completed: 1, total: 4, percent: 25 } }
    end

    def serialize(entity, obj)
      entity.represent(obj).serializable_hash
    end

    it 'nenhum card carrega a chave `progress` em qualquer profundidade' do
      [project_card, cell_card, robot_card].each do |card|
        h = serialize(Api::Entities::HierarchyCard, card)
        expect(ProgressKeyScanner.offending_paths(h)).to eq([]), "card vazou `progress`: #{h.inspect}"
      end
    end

    it 'o hub não carrega a chave `progress`' do
      h = serialize(Api::Entities::AnalyticsHub, hub)
      expect(ProgressKeyScanner.offending_paths(h)).to eq([])
    end

    it 'o card expõe `weighted_progress` no envelope rotulado (nunca um número solto)' do
      h = serialize(Api::Entities::HierarchyCard, project_card)
      expect(h[:weighted_progress]).to include(value: 40, metric: 'weighted')
      expect(h[:weighted_progress][:label]).to be_present
      expect(h).not_to have_key(:progress)
    end

    it 'o hub expõe `raw_completion` no envelope rotulado' do
      h = serialize(Api::Entities::AnalyticsHub, hub)
      expect(h[:raw_completion]).to include(completed: 1, total: 4, percent: 25, metric: 'raw_count')
      expect(h[:raw_completion][:label]).to be_present
    end

    it 'o card do robô expõe application e tasks_count; o de projeto, cells_count' do
      robot = serialize(Api::Entities::HierarchyCard, robot_card)
      expect(robot).to include(application: 'Solda', tasks_count: 4)
      expect(robot).not_to have_key(:cells_count)

      project = serialize(Api::Entities::HierarchyCard, project_card)
      expect(project).to include(cells_count: 4)
      expect(project).not_to have_key(:application)
    end
  end
end
