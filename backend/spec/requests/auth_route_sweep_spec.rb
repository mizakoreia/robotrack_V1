# frozen_string_literal: true

require 'rails_helper'

# Varredura de autenticação sobre TODA a superfície montada em Api::Root.
#
# Enumera as rotas reais do Grape, subtrai as que casam com
# Api::Root::PUBLIC_ROUTES, e exige 401 em cada uma das restantes — emitida duas
# vezes: sem header nenhum e com `X-Skip-Auth: 1`. Se o bypass voltar, a segunda
# emissão passa a responder algo diferente de 401 e o exemplo falha nomeando o
# método e o caminho.
#
# É o ancestral do route-sweep de `authorization-policies` (design §D-A): o
# formato do dado (`Api::Root.routes`) já está no lugar para aquela mudança
# estender em vez de reinventar.
RSpec.describe 'Varredura de autenticação das rotas', type: :request do
  # Converte uma rota do Grape num caminho concreto emitível: remove o sufixo de
  # formato, resolve `:version` pela versão declarada na própria rota e preenche
  # os demais segmentos dinâmicos com um id qualquer.
  def self.concrete_path(route)
    version = Array(route.version).first || 'v1'
    route.path
         .sub(/\(\.:format\)\z/, '')
         .sub('/:version', "/#{version}")
         .gsub(%r{/:[^/]+}, '/1')
  end

  # Caminho casa QUALQUER padrão público (agnóstico de método) — usado no teste
  # negativo "não abre nenhuma rota removida".
  def self.pattern_of(entry) = entry.is_a?(Array) ? entry[1] : entry

  def public_path?(path)
    Api::Root::PUBLIC_ROUTES.any? { |entry| self.class.pattern_of(entry).match?(path) }
  end

  # (método, caminho) de tudo que exige autenticação — agora CIENTE de método:
  # `DELETE /auth/v1/session` (logout) é protegido mesmo com `POST` público na
  # mesma rota.
  protected_routes = Api::Root.routes.filter_map do |route|
    path = concrete_path(route)
    method = route.request_method.to_s.upcase
    next if method == 'HEAD'
    next if Api::Root.public_route?(method, path)

    [method, path]
  end.uniq

  it 'encontra rotas protegidas para varrer' do
    # Uma lista vazia tornaria todos os exemplos abaixo vacuamente verdes.
    expect(protected_routes).not_to be_empty
  end

  describe 'sem header Authorization' do
    protected_routes.each do |method, path|
      it "#{method} #{path} responde 401" do
        send(method.downcase, path)
        expect(response).to have_http_status(:unauthorized),
                            "#{method} #{path} respondeu #{response.status}, esperado 401"
      end
    end
  end

  # O mesmo sweep, agora com o header que antes desligava a autenticação inteira.
  describe 'com X-Skip-Auth: 1' do
    protected_routes.each do |method, path|
      it "#{method} #{path} responde 401 mesmo com o header de bypass" do
        send(method.downcase, path, headers: { 'X-Skip-Auth' => '1' })
        expect(response).to have_http_status(:unauthorized),
                            "#{method} #{path} respondeu #{response.status} com X-Skip-Auth: 1, " \
                            'esperado 401 — o bypass de autenticação voltou'
      end
    end
  end

  describe 'a allowlist em si' do
    it 'contém exatamente os padrões públicos previstos (POST em session/registration)' do
      expect(Api::Root::PUBLIC_ROUTES.size).to eq(6)
      expect(Api::Root.public_route?('POST', '/auth/v1/session')).to be(true)
      expect(Api::Root.public_route?('POST', '/auth/v1/registration')).to be(true)
      expect(Api::Root.public_route?('GET', '/swagger_doc')).to be(true)
      expect(Api::Root.public_route?('GET', '/api/v1/countries')).to be(true)
      expect(Api::Root.public_route?('GET', '/auth/v1/oauth/google_url')).to be(true)
      expect(Api::Root.public_route?('POST', '/auth/v1/oauth/callback')).to be(true)
    end

    it 'mantém a auth sensível PROTEGIDA (allowlist ancorada, D4.8)' do
      # `^/auth/v1/session/?$` não casa renew; me e logout (DELETE) exigem token.
      expect(Api::Root.public_route?('POST', '/auth/v1/session/renew')).to be(false)
      expect(Api::Root.public_route?('GET', '/auth/v1/me')).to be(false)
      expect(Api::Root.public_route?('DELETE', '/auth/v1/session')).to be(false)
    end

    it 'não abre nenhuma rota dos módulos removidos' do
      %w[
        /auth/v1/magic_login/request_code
        /auth/v1/code_validation
        /auth/v1/pre_register
        /auth/v1/verify_code
        /auth/v1/complete_registration
        /auth/v1/checkout/session
        /whats/v1/webhooks/messages-upsert
      ].each do |path|
        expect(public_path?(path)).to be(false), "#{path} não deveria estar na allowlist"
      end
    end

    it 'está congelada' do
      expect(Api::Root::PUBLIC_ROUTES).to be_frozen
    end
  end

  describe 'o header de bypass não existe mais no código-fonte' do
    it 'não há ocorrência de X-Skip-Auth em app/' do
      hits = Dir.glob(Rails.root.join('app/**/*.rb')).select do |file|
        File.read(file).match?(/X-Skip-Auth|X_SKIP_AUTH/)
      end
      expect(hits).to be_empty
    end
  end
end
