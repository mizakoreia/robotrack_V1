# frozen_string_literal: true

module Api
  module Entities
    # my-tasks-view 3.2 (§3.6, D-MTV-4) — a LINHA achatada de "Minhas Tarefas".
    #
    # Recebe o Hash (chaves string) que `MyTasks::ListService` já montou com a
    # consulta única — expõe campo a campo, SEM resolver associação por método (o
    # que dispararia N+1 e destruiria o orçamento de 1 query de D-MTV-4). Cada linha
    # é autossuficiente: carrega os nomes+ids de robô/célula/projeto para o
    # deep-link (D-MTV-9), sem nenhuma requisição extra.
    class MyTaskRow < Grape::Entity
      expose(:id)           { |o, _| o['id'] }
      expose(:description)  { |o, _| o['description'] }
      expose(:status)       { |o, _| o['status'] }
      expose(:progress)     { |o, _| o['progress'] }
      expose(:category)     { |o, _| o['category'] }
      expose(:robot_id)     { |o, _| o['robot_id'] }
      expose(:robot_name)   { |o, _| o['robot_name'] }
      expose(:cell_id)      { |o, _| o['cell_id'] }
      expose(:cell_name)    { |o, _| o['cell_name'] }
      expose(:project_id)   { |o, _| o['project_id'] }
      expose(:project_name) { |o, _| o['project_name'] }
    end
  end
end
