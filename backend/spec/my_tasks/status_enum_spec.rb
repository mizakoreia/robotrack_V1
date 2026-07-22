# frozen_string_literal: true

require 'rails_helper'

# my-tasks-view 2.3 (§2.2, D-MTV-5) — o índice parcial `idx_tasks_open_ws` e o
# filtro do service codificam `('Pendente','Em Andamento')`. Se `robot-tasks`
# adicionar um 5º status, o índice e o filtro divergem EM SILÊNCIO (o índice segue
# válido, só deixa de cobrir). Este spec trava o conjunto do enum e falha ruidoso,
# apontando para design.md D-MTV-5.
RSpec.describe 'my-tasks-view — enum de status travado (D-MTV-5)' do
  it 'task_status tem EXATAMENTE os 4 status pt-BR, nesta ordem' do
    labels = ActiveRecord::Base.connection.exec_query(<<~SQL).rows.flatten
      SELECT e.enumlabel
      FROM pg_enum e
      JOIN pg_type t ON t.oid = e.enumtypid
      WHERE t.typname = 'task_status'
      ORDER BY e.enumsortorder
    SQL

    expect(labels).to eq(['Pendente', 'Em Andamento', 'Concluído', 'N/A']),
                      "enum task_status mudou — revise idx_tasks_open_ws e o filtro de " \
                      "MyTasks::ListService (design.md D-MTV-5). Encontrado: #{labels.inspect}"
  end
end
