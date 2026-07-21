# frozen_string_literal: true

require 'rails_helper'

# robot-tasks 6.2 (§2.2, D-RT-3) — a FRONTEIRA da capacidade. `progress` e
# `status` são colunas com constraint, mas READ-ONLY aqui: a máquina de estados
# §2.2 (e `task_advances`, o modal de avanço, a auto-atribuição) é de
# `progress-advances`. Este spec falha se `progress-advances` for antecipado
# dentro desta capacidade — o que criaria DOIS donos da transição.
RSpec.describe 'Fronteira de capacidade de robot-tasks', :tenancy do
  let(:conn) { ActiveRecord::Base.connection }
  let(:ana)  { create(:user) }
  let(:ws)   { make_workspace(owner: ana) }

  def robot_in(workspace)
    in_workspace(workspace) do
      projeto = Project.create!(name: 'Linha')
      celula = Cell.create!(project_id: projeto.id, name: 'Célula')
      Robot.create!(cell_id: celula.id, name: 'R-01')
    end
  end

  # NOTA: `task_advances` e a máquina de estados JÁ EXISTEM — são de
  # `progress-advances` (change posterior, empilhada). A asserção original
  # ("task_advances não existe") era a prova de que robot-tasks NÃO a antecipou;
  # cumprido o seu papel, foi substituída pela garantia que permanece verdadeira
  # abaixo: os services de robot-tasks não MUTAM progress/status.

  it 'os 5 services de CRUD de robot-tasks existem; não há service que RECORD avanço aqui' do
    nomes = Dir.glob(Rails.root.join('app/services/tasks/*.rb')).map { |f| File.basename(f, '.rb') }
    expect(nomes).to include('list_service', 'create_service', 'update_service', 'delete_service', 'assignees_service')
    # O registro de avanço vive em `app/services/task_advances/` (progress-advances),
    # não aqui. `apply_transition_service` (calculadora pura da transição) é
    # tolerado — ele NÃO persiste (provado abaixo).
    expect(defined?(Tasks::AdvanceService)).to be_nil
  end

  it 'nenhum service de tarefa muta progress ou status (só os lê / calcula a transição)' do
    fontes = Dir.glob(Rails.root.join('app/services/tasks/*.rb')).map { |f| File.read(f) }.join("\n")
    # Atribuição a progress/status (`self.progress =`, `.status =`, `update(progress:`)
    # não pode existir. Leitura no snapshot e cálculo puro (`Result.new(status:)`)
    # são permitidos — o `ApplyTransitionService` só devolve o par, não persiste.
    expect(fontes).not_to match(/\.(progress|status)\s*=(?!=)/)
    expect(fontes).not_to match(/update!?\([^)]*\b(progress|status):/)
  end

  it 'uma tarefa criada nasce Pendente/0 e nada nesta capacidade a transiciona' do
    robo = robot_in(ws)
    tarefa = in_workspace(ws) do
      Tasks::CreateService.new(context: nil).call(robot_id: robo.id, cat: 'A. Hardware', desc: 'Nova')
    end
    record = tarefa[:data][:record]
    expect([record.progress, record.status]).to eq([0, 'Pendente'])

    # O update de descrição não toca progress/status.
    in_workspace(ws) do
      Tasks::UpdateService.new(context: nil).call(id: record.id, desc: 'Editada', lock_version: record.lock_version)
    end
    recarregada = in_workspace(ws) { Task.find(record.id) }
    expect([recarregada.progress, recarregada.status, recarregada.desc]).to eq([0, 'Pendente', 'Editada'])
  end
end
