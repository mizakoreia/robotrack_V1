# frozen_string_literal: true

module Notifications
  # notification-preferences G6 (§D-P8) — publica o evento ESTRUTURAL pós-commit
  # (criar/excluir projeto/célula/robô/tarefa). MATERIALIZA o galho (ctx) e os
  # rótulos a partir do registro AQUI, no momento do disparo, e passa tudo na
  # payload: o delete é soft-delete e o job roda assíncrono, então re-buscar a
  # entidade excluída seria frágil (DE-G6.4).
  #
  # Best-effort no idioma da casa (mesmo `publish_event` do avanço): o disparo
  # acontece FORA da transação de hierarquia (pós-commit por construção — um
  # rollback nunca chega aqui) e qualquer erro só é logado, NUNCA derruba a
  # operação nem a resposta HTTP. Ator sem `Person` → não dispara (DE-G6.6).
  module StructureEvent
    module_function

    def publish(entity:, action:, record:, actor_person:)
      return if actor_person.nil?

      ctx, label, parent = describe(entity, record)
      ActiveSupport::Notifications.instrument(
        'structure.changed',
        workspace_id: record.workspace_id, actor_person_id: actor_person.id, author: actor_person.name,
        entity: entity.to_s, action: action.to_s, label: label, parent: parent, ctx: ctx
      )
    rescue StandardError => e
      Rails.logger.error(
        { event: 'structure_publish_failed', entity: entity.to_s, action: action.to_s, error: e.message }.to_json
      )
    end

    # Devolve [ctx, label, parent]. `ctx` sobe até o nível da entidade (os pais
    # ainda estão vivos: excluir um robô é soft-delete e não toca a célula). O
    # rótulo do pai casa o texto do locale: célula→projeto, robô→célula,
    # tarefa→robô ("Nome - Aplicação", como as demais notificações).
    def describe(entity, record)
      case entity.to_sym
      when :project
        [{ project_id: record.id }, record.name, nil]
      when :cell
        project = ::Project.find_by(id: record.project_id)
        [{ project_id: record.project_id, cell_id: record.id }, record.name, project&.name]
      when :robot
        cell = ::Cell.find_by(id: record.cell_id)
        [{ project_id: cell&.project_id, cell_id: record.cell_id, robot_id: record.id },
         "#{record.name} - #{record.application}", cell&.name]
      when :task
        robot = ::Robot.find_by(id: record.robot_id)
        cell = robot && ::Cell.find_by(id: robot.cell_id)
        parent = robot ? "#{robot.name} - #{robot.application}" : nil
        [{ project_id: cell&.project_id, cell_id: robot&.cell_id, robot_id: record.robot_id, task_id: record.id },
         record.desc, parent]
      end
    end
  end
end
