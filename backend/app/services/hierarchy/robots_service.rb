# frozen_string_literal: true

module Hierarchy
  # Robô: valida `application` contra a lista da §1.2 ANTES do banco (o CHECK é
  # o backstop); ausente sai como default 'Misto / Geral', nunca NULL (4.3).
  class RobotsService < CrudService
    MODEL = Robot
    PARENT_KEY = :cell_id
    PARENT_MODEL = Cell

    def create(id:, name:, parent_id: nil, extra: {})
      application = extra[:application]
      if application.present? && !Robot::APPLICATIONS.include?(application)
        return error_response('invalid_application', 422, details: { allowed: Robot::APPLICATIONS })
      end

      super(id: id, name: name, parent_id: parent_id, extra: extra.compact)
    end
  end
end
