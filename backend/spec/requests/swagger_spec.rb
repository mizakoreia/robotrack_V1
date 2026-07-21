# frozen_string_literal: true

require 'rails_helper'

# A versão do template batia em http://localhost:3000 com Net::HTTP e dava
# `skip` quando não havia servidor — ou seja, nunca rodava em CI. Aqui a
# superfície é exercitada pelo próprio rack de teste.
RSpec.describe 'Swagger e superfície da API', type: :request do
  # Superfície pública declarada no proposal §Impact, após a redução.
  SUPERFICIE_ESPERADA = %w[
    /auth/v1/session
    /auth/v1/registration
    /auth/v1/me
    /api/v1/users
    /api/v1/uploads
    /api/v1/countries
    /api/v1/downloads
    /api/v1/workspaces
    /api/v1/invitations
    /api/v1/memberships
    /api/v1/projects
    /api/v1/cells
    /api/v1/robots
    /api/v1/task_templates
    /api/v1/meta
  ].freeze

  it 'serve /swagger_doc como JSON sem autenticação' do
    get '/swagger_doc'

    expect(response).to have_http_status(:ok)
    expect(response.content_type).to include('application/json')
  end

  it 'documenta apenas a superfície reduzida' do
    get '/swagger_doc'
    paths = JSON.parse(response.body)['paths'].keys

    expect(paths).not_to be_empty
    fora_do_previsto = paths.reject { |path| SUPERFICIE_ESPERADA.any? { |prefixo| path.start_with?(prefixo) } }
    expect(fora_do_previsto).to be_empty
  end

  it 'não documenta nenhum endpoint dos módulos removidos' do
    get '/swagger_doc'
    paths = JSON.parse(response.body)['paths'].keys

    # Casa por segmento de caminho: `/api/v1/users/find_by_whatsapp` é de Users
    # e sobrevive — não é o módulo /whats/v1 que foi removido.
    removidos = %r{^/(whats|api/v1/(leads|lead_messages|operations|permissions|analytics))|/auth/v1/(checkout|magic_login|code_validation|pre_register|verify_code|complete_registration)}

    expect(paths.grep(removidos)).to be_empty
  end

  it 'usa o nome da aplicação no título, sem branding herdado' do
    get '/swagger_doc'
    info = JSON.parse(response.body)['info']

    expect(info.to_s).not_to match(/polemk/i)
  end
end
