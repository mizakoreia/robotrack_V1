# frozen_string_literal: true

require 'rails_helper'

# Tarefas 1.3–1.5 — as policies de recurso mapeiam operações para as 8 actions
# da matriz; nenhuma compara papel (o cop do G6 garante isso estaticamente,
# este spec garante o comportamento).
RSpec.describe 'Policies de recurso' do
  papel = Struct.new(:role, :person) do
    def member? = !role.nil?
  end
  owner = papel.new(:owner)
  edit  = papel.new(:edit)
  view  = papel.new(:view)
  nulo  = papel.new(nil)

  describe 'comissionamento (§4.1 L2)' do
    it 'ProjectPolicy.destroy? — edit true, view false' do
      expect(ProjectPolicy.destroy?(edit)).to be(true)
      expect(ProjectPolicy.destroy?(view)).to be(false)
    end

    it 'view lê, não muta, em todos os recursos de comissionamento' do
      [ProjectPolicy, CellPolicy, RobotPolicy, TaskPolicy].each do |policy|
        expect(policy.index?(view)).to be(true)
        expect(policy.show?(view)).to be(true)
        expect(policy.create?(view)).to be(false)
        expect(policy.update?(view)).to be(false)
        expect(policy.destroy?(view)).to be(false)
      end
    end
  end

  describe 'avanço, atribuição e reordenação (§4.1 L3)' do
    it 'view não registra avanço, não atribui, não reordena' do
      expect(AdvancePolicy.create?(view)).to be(false)
      expect(TaskPolicy.assign?(view)).to be(false)
      expect(ProjectPolicy.reorder?(view)).to be(false)
    end

    it 'edit faz os três' do
      expect(AdvancePolicy.create?(edit)).to be(true)
      expect(TaskPolicy.assign?(edit)).to be(true)
      expect(ProjectPolicy.reorder?(edit)).to be(true)
    end
  end

  describe 'catálogo (§4.1 L4)' do
    it 'view não edita tarefas-base nem responsáveis' do
      expect(TaskTemplatePolicy.create?(view)).to be(false)
      expect(PersonPolicy.create?(view)).to be(false)
      expect(TaskTemplatePolicy.create?(edit)).to be(true)
      expect(PersonPolicy.create?(edit)).to be(true)
    end
  end

  describe 'auditoria (§4.1 L5, inv. 3, D3.9)' do
    it 'AuditLogPolicy NÃO responde a update?/destroy? — a ausência é o contrato' do
      expect(AuditLogPolicy).not_to respond_to(:update?)
      expect(AuditLogPolicy).not_to respond_to(:destroy?)
    end

    it 'view lê o log mas não cria' do
      expect(AuditLogPolicy.index?(view)).to be(true)
      expect(AuditLogPolicy.create?(view)).to be(false)
      expect(AuditLogPolicy.create?(edit)).to be(true)
    end
  end

  describe 'notificações (§4.1 L6, inv. 4)' do
    minha  = Struct.new(:recipient_person_id).new('p-1')
    alheia = Struct.new(:recipient_person_id).new('p-2')
    clara  = papel.new(:view, Struct.new(:id).new('p-1'))

    it 'qualquer papel marca a PRÓPRIA como lida' do
      expect(NotificationPolicy.mark_read?(clara, minha)).to be(true)
    end

    it 'ninguém marca a alheia (divergência D-A: endurecimento sobre o legado)' do
      expect(NotificationPolicy.mark_read?(clara, alheia)).to be(false)
    end

    it 'view não cria notificação (§4.1 L5)' do
      expect(NotificationPolicy.create?(view)).to be(false)
    end
  end

  describe 'workspace (§4.1 L8) e membros (§4.1 L7)' do
    it 'destruir/reset é só do dono' do
      expect(WorkspacePolicy.destroy?(edit)).to be(false)
      expect(WorkspacePolicy.factory_reset?(edit)).to be(false)
      expect(WorkspacePolicy.destroy?(owner)).to be(true)
    end

    it 'renomear é manage_catalog — edit pode' do
      expect(WorkspacePolicy.update?(edit)).to be(true)
      expect(WorkspacePolicy.update?(view)).to be(false)
    end

    it 'gestão de membros e convites é só do dono' do
      expect(MembershipPolicy.update?(edit)).to be(false)
      expect(InvitationPolicy.create?(edit)).to be(false)
      expect(MembershipPolicy.update?(owner)).to be(true)
      expect(InvitationPolicy.create?(owner)).to be(true)
    end
  end

  describe 'BasePolicy.authorize!' do
    it 'não-membro levanta NotFound (vira 404, D3.6)' do
      expect { ProjectPolicy.authorize!(nulo, :index) }
        .to raise_error(Authorization::NotFound)
    end

    it 'membro sem papel suficiente levanta Forbidden (403)' do
      expect { ProjectPolicy.authorize!(view, :destroy) }
        .to raise_error(Authorization::Forbidden)
    end

    it 'papel suficiente retorna true' do
      expect(ProjectPolicy.authorize!(edit, :destroy)).to be(true)
    end
  end
end
