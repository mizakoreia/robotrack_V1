# frozen_string_literal: true

require 'rails_helper'

# commissioning-hierarchy 2.1–2.4 — models, WorkspaceScoped, PositionScoped e
# as invariantes de nome, provadas contra o BANCO (constraint, não validação).
RSpec.describe 'Models da hierarquia', :tenancy do
  let(:ana) { create(:user) }
  let(:ws)  { make_workspace(owner: ana) }

  def novo_projeto(nome, workspace = ws)
    in_workspace(workspace) { Project.create!(name: nome) }
  end

  describe 'nome (D-H8 — a constraint mora no banco)' do
    it 'rejeita nome em branco e nome só de espaços' do
      expect { novo_projeto('') }.to raise_error(ActiveRecord::StatementInvalid, /chk_projects_name/)
      expect { novo_projeto('   ') }.to raise_error(ActiveRecord::StatementInvalid, /chk_projects_name/)
    end

    it 'rejeita nome de 121 caracteres e aceita 120' do
      expect { novo_projeto('a' * 121) }.to raise_error(ActiveRecord::StatementInvalid, /chk_projects_name/)
      expect(novo_projeto('a' * 120).name.length).to eq(120)
    end

    it 'duplicata case-insensitive no MESMO escopo colide; em escopo vizinho, não' do
      projeto = novo_projeto('Linha 1')
      in_workspace(ws) do
        Cell.create!(project_id: projeto.id, name: 'solda 01')
        expect { Cell.create!(project_id: projeto.id, name: 'Solda 01') }
          .to raise_error(ActiveRecord::RecordNotUnique, /lower_name/)
      end

      vizinho = novo_projeto('Linha 2')
      celula = in_workspace(ws) { Cell.create!(project_id: vizinho.id, name: 'Solda 01') }
      expect(celula).to be_persisted
    end
  end

  describe 'PositionScoped (D-H3)' do
    it 'posições nascem contíguas 0-based por escopo' do
      p0 = novo_projeto('P0')
      p1 = novo_projeto('P1')
      expect([p0.position, p1.position]).to eq([0, 1])

      in_workspace(ws) do
        c0 = Cell.create!(project_id: p0.id, name: 'C0')
        expect(c0.position).to eq(0)
        expect(Cell.create!(project_id: p1.id, name: 'C0 do outro').position).to eq(0)
        expect(Robot.create!(cell_id: c0.id, name: 'R1').position).to eq(0)
        expect(Robot.create!(cell_id: c0.id, name: 'R2').position).to eq(1)
      end
    end
  end

  describe 'WorkspaceScoped + RLS' do
    it 'exclusão de projeto cascateia célula e robô num DELETE de banco' do
      projeto = novo_projeto('Cascata')
      in_workspace(ws) do
        celula = Cell.create!(project_id: projeto.id, name: 'C')
        Robot.create!(cell_id: celula.id, name: 'R')

        projeto.destroy!
        expect(Cell.count).to eq(0)
        expect(Robot.count).to eq(0)
      end
    end

    it 'application fora do CHECK é rejeitada pelo banco (D-H10)' do
      projeto = novo_projeto('Apps')
      in_workspace(ws) do
        celula = Cell.create!(project_id: projeto.id, name: 'C')
        robo = Robot.create!(cell_id: celula.id, name: 'R')
        expect(robo.application).to eq('Misto / Geral')

        expect do
          ActiveRecord::Base.connection.execute(
            "UPDATE robots SET application = 'Pintura' WHERE id = '#{robo.id}'"
          )
        end.to raise_error(ActiveRecord::StatementInvalid, /chk_robots_application/)
      end
    end
  end
end
