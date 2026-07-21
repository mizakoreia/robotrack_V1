# frozen_string_literal: true

require 'rails_helper'

# Reafirmação LITERAL das 8 linhas da §4.1 (tarefa 1.6, D3.2). Mudar a matriz
# exige mudar este spec junto — e o diff mostra exatamente qual linha da spec
# de produto foi alterada, em vez de um erro de integração distante.
RSpec.describe PermissionMatrix do
  it 'codifica as 8 linhas da §4.1, na ordem da tabela' do
    expect(described_class::ACTIONS).to eq(
      # §4.1 L1: "ver todo o conteúdo do workspace" — owner, edit, view
      read_workspace:         %i[owner edit view],
      # §4.1 L2: "criar/editar/excluir projeto, célula, robô, tarefa" — owner, edit
      manage_commissioning:   %i[owner edit],
      # §4.1 L3: "registrar avanço, atribuir, reordenar" — owner, edit
      record_progress:        %i[owner edit],
      # §4.1 L4: "editar catálogo de tarefas-base e responsáveis" — owner, edit
      manage_catalog:         %i[owner edit],
      # §4.1 L5: "criar log / notificação" — owner, edit
      create_log:             %i[owner edit],
      # §4.1 L6: "marcar a própria notificação como lida" — owner, edit, view
      mark_notification_read: %i[owner edit view],
      # §4.1 L7: "convidar, alterar papel, remover membro" — owner
      manage_membership:      %i[owner],
      # §4.1 L8: "excluir workspace / reset de fábrica" — owner
      destroy_workspace:      %i[owner]
    )
  end

  it 'a matriz é congelada' do
    expect(described_class::ACTIONS).to be_frozen
  end

  describe '.allows?' do
    it 'decide pela linha da tabela' do
      expect(described_class.allows?(:manage_membership, :owner)).to be(true)
      expect(described_class.allows?(:manage_membership, :edit)).to be(false)
      expect(described_class.allows?(:read_workspace, :view)).to be(true)
      expect(described_class.allows?(:destroy_workspace, :edit)).to be(false)
    end

    it 'aceita papel como string' do
      expect(described_class.allows?(:record_progress, 'edit')).to be(true)
    end

    it 'nega papel nulo (não-membro) em todas as actions' do
      described_class::ACTIONS.each_key do |action|
        expect(described_class.allows?(action, nil)).to be(false)
      end
    end

    it 'action desconhecida levanta KeyError, nunca false silencioso' do
      expect { described_class.allows?(:transfer_ownership, :owner) }
        .to raise_error(KeyError)
    end
  end
end
