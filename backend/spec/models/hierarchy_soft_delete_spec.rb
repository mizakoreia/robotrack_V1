# frozen_string_literal: true

require 'rails_helper'

# hierarchy-soft-delete G1 (§2.9, §2.1, D1, D2, D5, D7) — o ESQUEMA do soft-delete:
# a coluna `deleted_at` + o `default_scope`, o índice de nome parcial, a `position`
# nullable, e as views de progresso que passam a excluir o arquivado.
#
# Aqui o "arquivar" é feito à mão (setar `deleted_at` + `position = NULL`), porque o
# serviço de cascade só chega no G2. Este spec prova a FUNDAÇÃO no banco.
RSpec.describe 'Soft-delete da hierarquia (esquema)', :tenancy do
  let(:ana) { create(:user, name: 'Ana Dona') }
  let(:ws)  { make_workspace(owner: ana) }

  # Arquiva o nó como o serviço do G2 fará: `deleted_at` carimbado e `position`
  # zerada (D1 — sai do domínio da constraint DEFERRABLE de posição).
  def archive!(klass, id)
    in_workspace(ws) { klass.where(id: id).update_all(deleted_at: Time.current, position: nil) }
  end

  def view_value(view, key_col, id)
    in_workspace(ws) do
      ActiveRecord::Base.connection.select_value(
        ActiveRecord::Base.sanitize_sql_array(
          ["SELECT value FROM #{view} WHERE #{key_col} = ?", id]
        )
      )
    end
  end

  it 'default_scope esconde o arquivado; unscoped ainda o traz' do
    robo_id = in_workspace(ws) do
      proj = Project.create!(name: 'Linha')
      cell = Cell.create!(project_id: proj.id, name: 'Célula')
      Robot.create!(cell_id: cell.id, name: 'R-014').id
    end
    archive!(Robot, robo_id)

    in_workspace(ws) do
      expect(Robot.where(id: robo_id)).to be_empty
      expect(Robot.unscoped.where(id: robo_id)).to be_present
      expect(Robot.unscoped.find(robo_id).position).to be_nil # D1
    end
  end

  it 'nome de nó arquivado fica livre para reuso no mesmo escopo (D2)' do
    cell_id = in_workspace(ws) do
      proj = Project.create!(name: 'Linha')
      Cell.create!(project_id: proj.id, name: 'Célula').id
    end
    velho = in_workspace(ws) { Robot.create!(cell_id: cell_id, name: 'R-014').id }
    archive!(Robot, velho)

    novo = in_workspace(ws) { Robot.create!(cell_id: cell_id, name: 'R-014') }
    expect(novo).to be_persisted
    expect(novo.id).not_to eq(velho)
  end

  it 'índice parcial ainda barra nome duplicado entre VIVOS' do
    cell_id = in_workspace(ws) do
      proj = Project.create!(name: 'Linha')
      Cell.create!(project_id: proj.id, name: 'Célula').id
    end
    in_workspace(ws) { Robot.create!(cell_id: cell_id, name: 'R-014') }
    expect do
      in_workspace(ws) { Robot.create!(cell_id: cell_id, name: 'R-014') }
    end.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it 'robô arquivado deixa de arrastar a média ponderada da célula (D5)' do
    ids = in_workspace(ws) do
      proj = Project.create!(name: 'Linha')
      cell = Cell.create!(project_id: proj.id, name: 'Célula')
      cheio = Robot.create!(cell_id: cell.id, name: 'R-100', position: 0)
      vazio = Robot.create!(cell_id: cell.id, name: 'R-000', position: 1)
      create_task(cheio, desc: 'ok', weight: 1, progress: 100, status: 'Concluído', position: 0)
      create_task(vazio, desc: 'pend', weight: 1, progress: 0, status: 'Pendente', position: 0)
      { cell: cell.id, vazio: vazio.id }
    end

    expect(view_value('cell_weighted_progress', 'cell_id', ids[:cell]).to_i).to eq(50)
    archive!(Robot, ids[:vazio])
    expect(view_value('cell_weighted_progress', 'cell_id', ids[:cell]).to_i).to eq(100)
  end

  it 'tarefas de robô arquivado saem da contagem crua do escopo pai (D5)' do
    ids = in_workspace(ws) do
      proj = Project.create!(name: 'Linha')
      cell = Cell.create!(project_id: proj.id, name: 'Célula')
      robo = Robot.create!(cell_id: cell.id, name: 'R', position: 0)
      create_task(robo, desc: 't1', weight: 1, progress: 100, status: 'Concluído', position: 0)
      create_task(robo, desc: 't2', weight: 1, progress: 0, status: 'Pendente', position: 1)
      { cell: cell.id, robot: robo.id }
    end

    row = in_workspace(ws) do
      ActiveRecord::Base.connection.select_one(
        ActiveRecord::Base.sanitize_sql_array(
          ["SELECT completed, total FROM subtree_raw_completion WHERE scope_type='cell' AND scope_id = ?", ids[:cell]]
        )
      )
    end
    expect(row).to include('completed' => 1, 'total' => 2)

    # Arquivar o robô arquiva as tarefas dele também (cascade do G2); aqui simulo
    # marcando as tarefas, o que é o efeito observável: somem da contagem.
    in_workspace(ws) { Task.where(robot_id: ids[:robot]).update_all(deleted_at: Time.current) }
    archive!(Robot, ids[:robot])

    row2 = in_workspace(ws) do
      ActiveRecord::Base.connection.select_one(
        ActiveRecord::Base.sanitize_sql_array(
          ["SELECT completed, total FROM subtree_raw_completion WHERE scope_type='cell' AND scope_id = ?", ids[:cell]]
        )
      )
    end
    expect(row2).to include('completed' => 0, 'total' => 0)
  end
end
