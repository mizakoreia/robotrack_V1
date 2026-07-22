# frozen_string_literal: true

module Hierarchy
  # commissioning-hierarchy 4.1–4.3 — CRUD dos três níveis num contrato só.
  #
  # A autorização já aconteceu no gate (authorization-policies); aqui moram as
  # decisões de D-H1/D-H2 (id do cliente), D-H8 (nome), D-H9 (lock_version) e
  # D-H6 (exclusão auditada na MESMA transação). O 404 é UNIFORME: recurso
  # inexistente e recurso de outro tenant respondem byte-a-byte igual — a RLS
  # esconde a linha e este código não consegue (nem deve) distinguir.
  class CrudService
    include ApiResponseHandler

    def initialize(context:)
      @context = context
    end

    def create(id:, name:, parent_id: nil, extra: {})
      case IdValidator.verdict(id)
      when :nil_uuid  then return error_response('invalid_id_nil_uuid', 422)
      when :malformed then return error_response('invalid_id_format', 422)
      end
      return error_response('invalid_name', 422) unless valid_name?(name)

      if parent_key
        return error_response('not_found', 404) if parent_model.find_by(id: parent_id).nil?
      end

      attributes = { name: name.strip }.merge(extra)
      attributes[:id] = id if id.present?
      attributes[parent_key] = parent_id if parent_key
      attributes[:updated_by_person_id] = @context&.person&.id

      result = IdempotentCreate.call(model: model, attributes: attributes,
                                     match_keys: [:name, parent_key].compact)
      case result.outcome
      when :created
        cascade_after_create(result.record) # progress-rollup 2.4
        success_response({ record: result.record }, 201)
      when :replay     then success_response({ record: result.record }, 200)
      when :conflict   then error_response('id_conflict', 409, details: snapshot(result.record))
      when :name_taken then error_response('name_taken', 409)
      when :not_found  then error_response('not_found', 404)
      end
    end

    def update(id:, lock_version:, name: nil, extra: {})
      record = model.find_by(id: id)
      return error_response('not_found', 404) if record.nil?
      return error_response('invalid_name', 422) if name && !valid_name?(name)

      if lock_version && record.lock_version != lock_version.to_i
        return error_response('stale_object', 409, details: snapshot(record))
      end

      record.assign_attributes({ name: name&.strip }.compact.merge(extra))
      record.updated_by_person_id = @context&.person&.id
      record.save!
      success_response({ record: record }, 200)
    rescue ActiveRecord::StaleObjectError
      error_response('stale_object', 409, details: snapshot(record.reload))
    rescue ActiveRecord::RecordNotUnique
      error_response('name_taken', 409)
    end

    def destroy(id:)
      record = model.find_by(id: id)
      return error_response('not_found', 404) if record.nil?

      model.transaction do
        audit_destroy!(record)
        parent = destroy_parent_ref(record) # capturar ANTES de destruir
        record.destroy!
        cascade_after_destroy(parent) # progress-rollup 2.4
      end
      success_response({}, 204)
    end

    private

    def model = self.class::MODEL
    def parent_key = self.class::PARENT_KEY
    def parent_model = self.class::PARENT_MODEL

    # progress-rollup 2.4 — a cascata por nível. Criar um robô/célula vazio muda a
    # média do pai (§2.1: robô vazio arrasta a célula para baixo).
    def cascade_after_create(record)
      case record
      when ::Robot   then ::Progress::CascadeRecompute.call(robot_id: record.id)
      when ::Cell    then ::Progress::CascadeRecompute.for_cell(cell_id: record.id)
      when ::Project then ::Progress::CascadeRecompute.for_project(project_id: record.id)
      end
    end

    # Antes de destruir, guarda o pai a recalcular (o registro some depois).
    def destroy_parent_ref(record)
      case record
      when ::Robot then [:cell, record.cell_id]
      when ::Cell  then [:project, record.project_id]
      end
    end

    def cascade_after_destroy(parent)
      return if parent.nil?

      case parent.first
      when :cell    then ::Progress::CascadeRecompute.for_cell(cell_id: parent.last)
      when :project then ::Progress::CascadeRecompute.for_project(project_id: parent.last)
      end
    end

    def valid_name?(name)
      name.to_s.strip.length.between?(1, 120)
    end

    def snapshot(record)
      { id: record.id, name: record.name, position: record.position, lock_version: record.lock_version }
    end

    # §2.8 / D-H6 — a auditoria acontece DENTRO da transação do DELETE. Hoje é
    # log estruturado; `audit-log` troca este método pela escrita em
    # `audit_logs` (aí sim "auditoria falhou → não exclui" ganha dente).
    # Decisão de execução 2 do EXECUCAO.md.
    def audit_destroy!(record)
      Rails.logger.info(
        {
          event: 'hierarchy_destroy',
          type: record.class.name,
          id: record.id,
          workspace_id: record.workspace_id,
          name: record.name,
          by_person_id: @context&.person&.id
        }.to_json
      )
    end
  end
end
