# frozen_string_literal: true

require 'rails_helper'

# tenant-isolation §"Rota de domínio fora da allowlist e sem contexto reprova o
# CI" (tarefa 4.6). Irmã da varredura de autenticação: enumera as rotas reais do
# Grape, subtrai as públicas e as isentas de tenant, e exige que cada rota de
# DOMÍNIO restante cobre `X-Workspace-Id` — sem o header, 400
# workspace_context_missing. Um endpoint de domínio novo que esqueça de passar
# pela resolução de tenant (ou de entrar na allowlist) reprova aqui, nomeando o
# verbo e o caminho.
RSpec.describe 'Varredura de tenant das rotas', :tenancy, type: :request do
  def self.concrete_path(route)
    version = Array(route.version).first || 'v1'
    route.path
         .sub(/\(\.:format\)\z/, '')
         .sub('/:version', "/#{version}")
         .gsub(%r{/:[^/]+}, '/1')
  end

  domain_routes = Api::Root.routes.filter_map do |route|
    path = concrete_path(route)
    method = route.request_method.to_s.upcase
    next if method == 'HEAD'
    next if Api::Root.public_route?(method, path)
    next if Api::Root.tenant_exempt?(method, path)

    [method, path]
  end.uniq

  let(:user) { create(:user) }

  it 'encontra ao menos uma rota de domínio para varrer' do
    # Vazio tornaria os exemplos abaixo vacuamente verdes. Hoje quem garante isso
    # é a sonda de tenancy (montada só em teste); a jusante serão os recursos reais.
    expect(domain_routes).not_to be_empty
  end

  domain_routes.each do |method, path|
    it "#{method} #{path} exige X-Workspace-Id (400 sem o header)" do
      send(method.downcase, path, headers: auth_headers(user))
      expect(response).to have_http_status(:bad_request),
                          "#{method} #{path} respondeu #{response.status} sem X-Workspace-Id, " \
                          'esperado 400 — a rota de domínio não passa pela resolução de tenant'
      expect(JSON.parse(response.body)['error']).to eq('workspace_context_missing')
    end
  end
end
