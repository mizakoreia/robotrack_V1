# frozen_string_literal: true

module Tasks
  # robot-tasks 3.2 (§3.5, D1, D-RT-7) — cria uma tarefa avulsa num robô, com uuid
  # do cliente e `position` = maior atual + 1.
  #
  # id duplicado → 409 (NÃO replay idempotente como a hierarquia: §1.1 é explícito
  # — "um segundo POST com o mesmo id retorna 409 sem criar duplicata"). `desc`
  # repetida no mesmo robô também é 409, pelo índice único da decisão 1.
  class CreateService
    include ApiResponseHandler

    def initialize(context:)
      @context = context
    end

    def call(robot_id:, cat:, desc:, id: nil)
      case Hierarchy::IdValidator.verdict(id)
      when :nil_uuid  then return error_response('invalid_id_nil_uuid', 422)
      when :malformed then return error_response('invalid_id_format', 422)
      end

      robot = ::Robot.find_by(id: robot_id)
      return error_response('not_found', 404) if robot.nil?

      attrs = { robot_id: robot_id, cat: cat, desc: desc, position: next_position(robot_id) }
      attrs[:id] = id if id.present?
      task = ::Task.new(attrs)

      if task.save
        success_response({ record: task }, 201)
      else
        error_response('validation_error', 422, details: task.errors.messages)
      end
    rescue ActiveRecord::RecordNotUnique => e
      error_response(e.message.include?('robot_lower_desc') ? 'desc_conflict' : 'id_conflict', 409)
    end

    private

    def next_position(robot_id)
      (::Task.where(robot_id: robot_id).maximum(:position) || -1) + 1
    end
  end
end
