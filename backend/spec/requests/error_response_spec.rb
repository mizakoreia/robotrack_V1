# frozen_string_literal: true

require 'rails_helper'

# O template serializava `e.backtrace.join` no corpo da resposta HTTP
# (`error!(error_backtrace)` em root.rb:123). Assertar "retorna 500" não pegaria
# essa regressão — o modo de falha concreto é o backtrace vazar, então é isso
# que se asserta.
RSpec.describe 'Resposta de erro 5xx', type: :request do
  let(:user) do
    UserType.seed_default_types!
    User.create!(name: 'OG de Teste', email: 'og-erro@example.com', user_type: UserType.og)
  end

  let(:token) { Auth::TokenService.new(user).generate_tokens[:token] }
  let(:auth) { { 'Authorization' => "Bearer #{token}" } }

  # Provoca uma exceção real no service que o endpoint de fato chama.
  before do
    allow(UsersService).to receive(:index).and_raise(RuntimeError, 'explosao proposital em spec')
  end

  it 'responde 500 sem vazar backtrace, com error/message/request_id' do
    get '/api/v1/users', headers: auth

    expect(response).to have_http_status(:internal_server_error)

    body = response.body
    expect(body).not_to match(/BACKTRACE/i)
    expect(body).not_to match(/\.rb:\d+/)
    expect(body).not_to match(%r{app/services})
    expect(body).not_to include('explosao proposital em spec')

    parsed = JSON.parse(body)
    expect(parsed['error']).to eq('internal_error')
    expect(parsed['message']).to eq('Erro interno no servidor')
    expect(parsed['request_id']).to be_present
  end

  it 'loga o backtrace com o mesmo request_id que devolveu ao cliente' do
    logged = []
    allow(Rails.logger).to receive(:error) { |line| logged << line.to_s }

    get '/api/v1/users', headers: auth

    request_id = JSON.parse(response.body)['request_id']
    entry = logged.find { |line| line.include?('api_error') }

    expect(entry).to be_present, 'nenhuma linha de api_error foi logada'
    parsed = JSON.parse(entry)
    expect(parsed['request_id']).to eq(request_id)
    expect(parsed['backtrace']).to be_an(Array).and be_present
    expect(parsed['message']).to include('explosao proposital em spec')
  end

  it 'não referencia mais ExceptionNotifier em lugar nenhum de app/' do
    hits = Dir.glob(Rails.root.join('app/**/*.rb')).select do |file|
      File.read(file).include?('ExceptionNotifier')
    end
    expect(hits).to be_empty
  end
end
