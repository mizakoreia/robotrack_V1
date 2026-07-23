# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('config/observability/scrubber')
require Rails.root.join('config/observability/log_fields')

# delivery-and-observability 4.1/4.3/4.5 — redação de PII e campos de log.
RSpec.describe Observability::Scrubber do
  it 'redige chaves sensíveis por substring, recursivo' do
    input = {
      'email' => 'a@b.com',
      'password' => 'segredo123',
      'nested' => { 'refresh_token' => 'rt', 'authorization' => 'Bearer x', 'ok' => 1 },
      'list' => [{ 'jwt' => 'e.y.z' }, { 'name' => 'Ana' }]
    }
    out = described_class.scrub(input)
    expect(out['email']).to eq('a@b.com')
    expect(out['password']).to eq('[FILTERED]')
    expect(out['nested']['refresh_token']).to eq('[FILTERED]')
    expect(out['nested']['authorization']).to eq('[FILTERED]')
    expect(out['nested']['ok']).to eq(1)
    expect(out['list'][0]['jwt']).to eq('[FILTERED]')
    expect(out['list'][1]['name']).to eq('Ana')
  end

  it 'invitation_token é redigido' do
    expect(described_class.scrub('invitation_token' => 'abc')).to eq('invitation_token' => '[FILTERED]')
  end

  it 'scrub_event cobre request/extra/contexts' do
    event = { 'request' => { 'password' => 'x' }, 'extra' => { 'token' => 'y' }, 'level' => 'error' }
    out = described_class.scrub_event(event)
    expect(out['request']['password']).to eq('[FILTERED]')
    expect(out['extra']['token']).to eq('[FILTERED]')
    expect(out['level']).to eq('error')
  end
end

RSpec.describe Observability::LogFields do
  it 'monta os campos do contexto sem levantar quando não há usuário' do
    fields = described_class.custom(
      { policy: 'ProjectPolicy', db_runtime: 12.345 },
      current: { request_id: 'req-1', user_id: nil, workspace_id: 'w1', actor_person_id: 'p1' }
    )
    expect(fields[:request_id]).to eq('req-1')
    expect(fields[:workspace_id]).to eq('w1')
    expect(fields[:person_id]).to eq('p1')
    expect(fields[:policy]).to eq('ProjectPolicy')
    expect(fields[:db_runtime]).to eq(12.3)
    expect(fields).not_to have_key(:user_id) # compact: nil sai, sem "user_id":null quebrando nada
  end
end
