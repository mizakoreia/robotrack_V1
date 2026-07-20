# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PolemkInstanceService do
  let!(:instance) do
    PolemkInstance.create!(
      display_name: 'Instância Primária',
      instance_name: 'PRIMARY_INSTANCE',
      instance_id: 'inst_primary',
      api_key: 'apikey_primary',
      integration: 'WHATSAPP-BAILEYS',
      is_qrcode: true,
      connection_status: 'connected',
      number: '5548999999999',
      raw_response: { init: true }
    )
  end

  describe '.get_instance' do
    it 'retorna a instância por instance_id' do
      result = PolemkInstanceService.get_instance({ instance_id: 'inst_primary' })
      expect(result[:status]).to eq(200)
      payload = result[:data].as_json
      expect(payload['instance_id']).to eq('inst_primary')
    end

    it 'retorna sempre a primeira instância quando não encontra por filtros' do
      result = PolemkInstanceService.get_instance({ instance_id: 'missing' })
      expect(result[:status]).to eq(200)
      payload = result[:data].as_json
      expect(payload['instance_id']).to eq('inst_primary')
    end

    it 'retorna 422 quando parâmetros conflitantes são enviados' do
      result = PolemkInstanceService.get_instance({ instance_id: 'x', instance_name: 'y' })
      expect(result[:status]).to eq(422)
    end
  end
end
