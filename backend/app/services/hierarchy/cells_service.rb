# frozen_string_literal: true

module Hierarchy
  # Célula: o pai (projeto) precisa ser visível sob RLS — criar célula sob
  # projeto de outro workspace responde 404, não 403 (tarefa 4.2, D3.6).
  class CellsService < CrudService
    MODEL = Cell
    PARENT_KEY = :project_id
    PARENT_MODEL = Project
  end
end
