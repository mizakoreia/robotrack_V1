# frozen_string_literal: true

require 'rails_helper'

# task-catalog 2.1–2.2 (§3.9, D-TC-2) — validações e a normalização de
# `app_filters` na ESCRITA. O que o console grava tem de ser o que a API grava.
RSpec.describe TaskTemplate, :tenancy do
  let(:ana) { create(:user) }
  let(:ws)  { make_workspace(owner: ana) }

  def criar(atributos = {})
    in_workspace(ws) { described_class.create!({ cat: 'A. Hardware', desc: 'Power On' }.merge(atributos)) }
  end

  describe 'validações' do
    it 'desc só de espaços é 422 e não cria linha' do
      expect { criar(desc: '   ') }.to raise_error(ActiveRecord::RecordInvalid, /Desc/)
      expect(in_workspace(ws) { described_class.count }).to eq(0)
    end

    it 'cat em branco é inválido' do
      expect { criar(cat: '') }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it 'weight zero ou negativo é inválido' do
      expect { criar(weight: 0) }.to raise_error(ActiveRecord::RecordInvalid, /Weight/)
      expect { criar(weight: -1) }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it 'aplica strip em cat e desc' do
      template = criar(cat: '  A. Hardware  ', desc: '  Power On  ')
      expect([template.cat, template.desc]).to eq(['A. Hardware', 'Power On'])
    end

    it 'filtro fora da §1.2 é inválido no model (o CHECK do banco é o backstop)' do
      expect { criar(app_filters: ['Pintura']) }
        .to raise_error(ActiveRecord::RecordInvalid, /§1\.2/)
    end
  end

  describe 'normalização de app_filters (D-TC-2)' do
    it '["Handling", "Misto / Geral"] persiste [] — a sentinela vence' do
      expect(criar(app_filters: ['Handling', 'Misto / Geral']).app_filters).to eq([])
    end

    it '"Todas" também colapsa para []' do
      expect(criar(app_filters: ['Todas']).app_filters).to eq([])
    end

    it 'lista vazia continua []' do
      expect(criar(app_filters: []).app_filters).to eq([])
    end

    it 'duplicatas somem, ordem preservada' do
      template = criar(app_filters: ['Sealing', 'Handling', 'Sealing'])
      expect(template.app_filters).to eq(['Sealing', 'Handling'])
    end

    it 'strings com espaço são normalizadas e vazias descartadas' do
      expect(criar(app_filters: ['  Sealing  ', '']).app_filters).to eq(['Sealing'])
    end
  end
end
