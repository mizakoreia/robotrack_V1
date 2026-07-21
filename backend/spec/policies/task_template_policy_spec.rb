# frozen_string_literal: true

require 'rails_helper'

# task-catalog 4.1 (§4.1 linhas 1 e 4, D3) — a policy do catálogo testada
# ISOLADAMENTE, sem passar por HTTP: leitura para os 3 papéis, escrita e
# sincronização só para owner/edit. `view` em qualquer escrita é `false`.
RSpec.describe TaskTemplatePolicy do
  papel = Struct.new(:role) do
    def member? = !role.nil?
  end
  let(:owner) { papel.new(:owner) }
  let(:edit)  { papel.new(:edit) }
  let(:view)  { papel.new(:view) }

  describe 'leitura (read_workspace: os 3 papéis)' do
    it 'index? e show? valem para owner, edit e view' do
      [owner, edit, view].each do |ctx|
        expect(described_class.index?(ctx)).to be(true)
        expect(described_class.show?(ctx)).to be(true)
      end
    end
  end

  describe 'escrita e sincronização (manage_catalog: owner/edit)' do
    it 'owner e edit criam, editam, excluem e sincronizam' do
      [owner, edit].each do |ctx|
        expect(described_class.create?(ctx)).to be(true)
        expect(described_class.update?(ctx)).to be(true)
        expect(described_class.destroy?(ctx)).to be(true)
        expect(described_class.sync?(ctx)).to be(true)
      end
    end

    it 'view não cria, não edita, não exclui, não sincroniza' do
      expect(described_class.create?(view)).to be(false)
      expect(described_class.update?(view)).to be(false)
      expect(described_class.destroy?(view)).to be(false)
      expect(described_class.sync?(view)).to be(false)
    end
  end

  describe 'fail-closed' do
    it 'papel nulo (não-membro) é false em toda ação' do
      nulo = papel.new(nil)
      %i[index? show? create? update? destroy? sync?].each do |acao|
        expect(described_class.public_send(acao, nulo)).to be(false)
      end
    end
  end
end
