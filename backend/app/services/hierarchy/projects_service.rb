# frozen_string_literal: true

module Hierarchy
  # Projeto: raiz — sem pai a validar (o workspace é o contexto da sessão).
  class ProjectsService < CrudService
    MODEL = Project
    PARENT_KEY = nil
    PARENT_MODEL = nil
  end
end
