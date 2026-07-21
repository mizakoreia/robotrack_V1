# frozen_string_literal: true

require 'rails_helper'

# task-catalog 3.3 / 3.5 / 3.6 (§1.3, D-TC-4) — o service de seed do catálogo:
# UM insert_all, ordenação determinística por collation binária e isolamento por
# workspace. `make_workspace` NÃO semeia (é o bootstrap real, G-anterior, que
# semeia); aqui o service é exercitado direto, dentro do contexto de tenant.
RSpec.describe Workspaces::SeedDefaultTaskTemplatesService, :tenancy do
  let(:ws) { make_workspace(owner: create(:user)) }

  def semear(workspace)
    in_workspace(workspace) { described_class.new(workspace_id: workspace.id).call }
  end

  describe 'semeadura' do
    it 'cria os 31 templates em 9 categorias, todos com weight 1' do
      semear(ws)
      in_workspace(ws) do
        expect(TaskTemplate.count).to eq(31)
        expect(TaskTemplate.distinct.count(:cat)).to eq(9)
        expect(TaskTemplate.where('weight <> 1').count).to eq(0)
      end
    end

    it 'grava os DOIS filtros de aplicação de §1.3 e nada mais' do
      semear(ws)
      in_workspace(ws) do
        com_filtro = TaskTemplate.where("app_filters <> '{}'").order(:desc)
        expect(com_filtro.count).to eq(2)
        expect(com_filtro.find_by(desc: 'Calibração de Cola').app_filters).to eq(['Sealing'])
        expect(com_filtro.find_by(desc: 'Check sinais de Gripper').app_filters)
          .to eq(['Handling', 'Solda Ponto'])
      end
    end

    it 'insere as 31 linhas com UMA única query (insert_all, não 31 INSERTs)' do
      inserts = 0
      sub = ActiveSupport::Notifications.subscribe('sql.active_record') do |*args|
        sql = args.last[:sql]
        inserts += 1 if sql =~ /INSERT INTO ["`]?task_templates/i
      end
      semear(ws)
      ActiveSupport::Notifications.unsubscribe(sub)

      expect(inserts).to eq(1)
    end
  end

  describe 'ordenação lexicográfica das categorias (3.5)' do
    before { semear(ws) }

    let(:categorias_esperadas) do
      [
        'A. Hardware', 'B. Rede', 'C. Segurança', 'D. Processo', 'E. Trajetórias',
        'F. Interlocks', 'G. Tryout', 'H. Otimização', 'I. Aceitação'
      ]
    end

    it 'o scope `ordered` do model devolve A. Hardware … I. Aceitação' do
      in_workspace(ws) do
        expect(TaskTemplate.ordered.map(&:cat).uniq).to eq(categorias_esperadas)
      end
    end

    # O ponto de §1.3 nota / D-TC-1: a ordem tem de ser a MESMA sob locale binário
    # (`C`) e sob locale pt-BR — sem `COLLATE "C"` explícita, a collation do
    # ambiente decidiria e a tela embaralharia as categorias só em produção.
    it 'produz a mesma ordem sob COLLATE "C" e sob COLLATE "pt-BR-x-icu"' do
      in_workspace(ws) do
        conn = ActiveRecord::Base.connection
        %w[C pt-BR-x-icu].each do |collation|
          cats = conn.select_values(<<~SQL)
            SELECT DISTINCT cat COLLATE "#{collation}" AS cat FROM task_templates
            WHERE workspace_id = #{conn.quote(ws.id)}
            ORDER BY cat COLLATE "#{collation}"
          SQL
          expect(cats).to eq(categorias_esperadas), "ordem divergiu sob COLLATE #{collation}"
        end
      end
    end
  end

  describe 'isolamento por workspace (3.6)' do
    it 'excluir Speed up no workspace A não afeta o catálogo do workspace B' do
      ws_b = make_workspace(owner: create(:user))
      semear(ws)
      semear(ws_b)

      in_workspace(ws) { TaskTemplate.find_by!(desc: 'Speed up').destroy! }

      expect(in_workspace(ws) { TaskTemplate.count }).to eq(30)
      expect(in_workspace(ws)   { TaskTemplate.exists?(desc: 'Speed up') }).to be(false)
      expect(in_workspace(ws_b) { TaskTemplate.count }).to eq(31)
      expect(in_workspace(ws_b) { TaskTemplate.exists?(desc: 'Speed up') }).to be(true)
    end
  end
end
