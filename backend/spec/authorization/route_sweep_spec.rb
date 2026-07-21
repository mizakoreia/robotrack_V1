# frozen_string_literal: true

require 'rails_helper'

# authorization-policies 5.1 / D3.5 — o route-sweep da superfície INTEIRA.
#
# É o mecanismo que impede a invariante 1 de apodrecer: um endpoint novo que
# não declare `route_setting :policy` nem esteja na allowlist pública reprova
# AQUI, em CI, com método + path exatos — antes de qualquer request de runtime.
# Substitui e engole o `policy_route_sweep_spec` de workspace-invitations
# (que cobria só convites/equipe): a varredura cresceu para 100% das rotas.
RSpec.describe 'Route-sweep de autorização (superfície inteira)', type: :request do
  PAPEL_NULO = Struct.new(:role).new(nil)

  # (método, path normalizado, rota) de tudo que o Grape monta em test.
  ROTAS = Api::Root.routes.filter_map do |route|
    path = route.path.sub(/\(\.:format\)\z/, '').sub('/:version', '/v1')
    method = route.request_method.to_s.upcase
    next if method == 'HEAD'

    [method, path, route]
  end

  # Caminho concreto para consultar PUBLIC_ROUTES (regex sobre paths reais).
  def self.concreto(path) = path.gsub(%r{/:[^/]+}, '/1')

  publicas, protegidas = ROTAS.partition { |m, p, _| Api::Root.public_route?(m, concreto(p)) }

  it 'encontra a superfície inteira (lista vazia seria vacuamente verde)' do
    expect(ROTAS.size).to be >= 20
  end

  describe 'toda rota protegida declara policy' do
    protegidas.each do |method, path, route|
      it "#{method} #{path}" do
        declarada = route.settings[:policy]
        expect(declarada).to be_present,
                             "#{method} #{path} não declara `route_setting :policy` nem consta da " \
                             'allowlist pública — endpoint sem decisão de autorização (inv. 1)'

        next if declarada[:access] == :authenticated

        policy = declarada.fetch(:policy).constantize
        metodo = "#{declarada.fetch(:action)}?"
        expect(policy.ancestors).to include(BasePolicy)
        expect(policy.public_send(metodo, PAPEL_NULO)).to be(false),
                                                          "#{policy}.#{metodo} autoriza papel NULO — tem de ser fail-closed"
      end
    end
  end

  describe 'a igualdade que fecha a conta (D3.5)' do
    it 'declaradas + públicas == total de rotas, sem resto' do
      sem_decisao = protegidas.reject { |_, _, route| route.settings[:policy].present? }
      mensagem = sem_decisao.map { |m, p, _| "  #{m} #{p}" }.join("\n")

      expect(sem_decisao).to be_empty, "rotas sem policy e fora da allowlist:\n#{mensagem}"
      expect(protegidas.size + publicas.size).to eq(ROTAS.size)
    end
  end

  describe 'a allowlist pública (config/authorization/public_routes.yml)' do
    entradas = Authorization::PublicRoutes.entries

    it 'toda rota pública do Grape está listada com reason' do
      publicas.each do |method, path, _|
        expect(Authorization::PublicRoutes.include?(method, path)).to be(true),
                                                                      "#{method} #{path} passa em PUBLIC_ROUTES mas não está em public_routes.yml — " \
                                                                      'a lista auditável divergiu da regex'
      end
    end

    it 'não tem entrada órfã — permissão morta falha' do
      entradas.each do |entry|
        existe = ROTAS.any? { |m, p, _| m == entry[:method] && p == entry[:path] }
        expect(existe).to be(true),
                          "public_routes.yml lista #{entry[:method]} #{entry[:path]}, que não existe mais nas " \
                          'rotas montadas — remover a entrada em vez de acumular permissão morta'
      end
    end

    it 'toda entrada é de fato pública pela regex de Api::Root (uma fonte, duas formas)' do
      entradas.each do |entry|
        expect(Api::Root.public_route?(entry[:method], self.class.concreto(entry[:path]))).to be(true),
                                                                                              "#{entry[:method]} #{entry[:path]} está no yml mas PUBLIC_ROUTES não o reconhece"
      end
    end

    it 'reason vazio é inválido (validado também no boot)' do
      Tempfile.create(['routes', '.yml']) do |f|
        f.write("- path: /x\n  method: GET\n  reason: \"\"\n")
        f.flush
        expect { Authorization::PublicRoutes.load!(f.path) }
          .to raise_error(ArgumentError, /reason|`reason`/)
      end
    end
  end
end
