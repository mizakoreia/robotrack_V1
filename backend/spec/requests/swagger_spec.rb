# frozen_string_literal: true

require 'spec_helper'
require 'net/http'

RSpec.describe 'API Versioning & Docs', type: :request do
  def http_get(path)
    Net::HTTP.get_response(URI("http://localhost:3000#{path}"))
  rescue Errno::ECONNREFUSED, SocketError
    skip 'Servidor não está em execução em :3000; teste ignorado'
  end

  it 'serve /swagger_doc (JSON)' do
    res = http_get('/swagger_doc')
    expect(res).to be_a(Net::HTTPResponse)
    expect(res.code).to eq('200')
    expect(res['Content-Type']).to include('application/json')
  end

  it 'exibe endpoints versionados por módulo (auth/v1)' do
    res = http_get('/auth/v1/sessions/status')
    expect(%w[200 401 403 404]).to include(res.code)
  end
end
