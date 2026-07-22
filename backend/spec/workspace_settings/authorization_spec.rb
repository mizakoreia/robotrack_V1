# frozen_string_literal: true

require 'rails_helper'

# workspace-settings 1.4 (§4.1, D3) — a matriz de autorização das policies desta
# change. As decisões-chave: escrita de equipe/catálogo é `manage_catalog`
# (owner/edit); backup e reset são `destroy_workspace` (SÓ o dono — `edit` com frase
# e backup corretos AINDA é 403, D-EXP-ROLE/D12). Testado no nível da policy
# (`.authorize!`); as negações por HTTP entram com os endpoints (G2/G4/G5).
RSpec.describe 'workspace-settings — matriz de autorização (1.4)' do
  def ctx(role) = Struct.new(:role, :member?).new(role, !role.nil?)

  describe 'WorkspaceSettingsPolicy (Equipe)' do
    it 'listar é de qualquer membro, inclusive view' do
      %i[owner edit view].each { |r| expect(WorkspaceSettingsPolicy.index?(ctx(r))).to be(true) }
    end

    it 'criar e arquivar pessoa são owner/edit; view é negado' do
      %i[create? archive?].each do |action|
        expect(WorkspaceSettingsPolicy.public_send(action, ctx(:owner))).to be(true)
        expect(WorkspaceSettingsPolicy.public_send(action, ctx(:edit))).to be(true)
        expect(WorkspaceSettingsPolicy.public_send(action, ctx(:view))).to be(false)
      end
    end
  end

  describe 'WorkspaceBackupPolicy (export) — owner-only (D-EXP-ROLE)' do
    it 'só o dono cria; edit e view são negados' do
      expect(WorkspaceBackupPolicy.create?(ctx(:owner))).to be(true)
      expect(WorkspaceBackupPolicy.create?(ctx(:edit))).to be(false)
      expect(WorkspaceBackupPolicy.create?(ctx(:view))).to be(false)
    end
  end

  describe 'WorkspaceFactoryResetPolicy — owner-only (D12)' do
    it 'só o dono; edit (mesmo com frase/backup corretos) é negado' do
      expect(WorkspaceFactoryResetPolicy.create?(ctx(:owner))).to be(true)
      expect(WorkspaceFactoryResetPolicy.create?(ctx(:edit))).to be(false)
      expect(WorkspaceFactoryResetPolicy.create?(ctx(:view))).to be(false)
    end

    it 'papel nil (não-membro) é negado em tudo' do
      expect(WorkspaceFactoryResetPolicy.create?(ctx(nil))).to be(false)
      expect(WorkspaceBackupPolicy.create?(ctx(nil))).to be(false)
      expect(WorkspaceSettingsPolicy.create?(ctx(nil))).to be(false)
    end
  end
end
