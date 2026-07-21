# frozen_string_literal: true

require 'rails_helper'

# Varredura de POLICIES sobre a superfície de convites e equipe
# (workspace-invitations 4.4 — o "route-sweep de D3" no piso que esta change
# entrega, decisão de execução 1).
#
# Irmã das varreduras de autenticação (Onda 2) e de tenant (Onda 1), e pelo mesmo
# motivo: a garantia não pode depender de alguém lembrar. Um endpoint novo de
# convite ou de equipe que não declare `route_setting :policy` reprova aqui,
# nomeando o verbo e o caminho. Quando `authorization-policies` entregar o
# mecanismo geral, é este spec que se estende para a superfície inteira.
RSpec.describe 'Varredura de policies das rotas de convite e equipe', type: :request do
  # Rotas de DOMÍNIO destas duas capacidades. Os dois caminhos por token ficam de
  # fora de propósito: não há papel a consultar (a pré-visualização é pública e a
  # autorização do aceite É a invariante 6, avaliada com a linha travada).
  SUPERFICIE = %r{^/api/v1/(invitations|memberships)}
  SEM_POLICY = [
    ['GET',  %r{^/api/v1/invitations/:token}],
    ['POST', %r{^/api/v1/invitations/:token/accept}]
  ].freeze

  def self.exempt?(method, path)
    SEM_POLICY.any? { |m, regex| m == method && regex.match?(path) }
  end

  rotas = Api::Root.routes.filter_map do |route|
    path = route.path.sub(/\(\.:format\)\z/, '').sub('/:version', '/v1')
    method = route.request_method.to_s.upcase
    next if method == 'HEAD'
    next unless SUPERFICIE.match?(path)
    next if exempt?(method, path)

    [method, path, route]
  end

  it 'encontra rotas para varrer (uma lista vazia seria vacuamente verde)' do
    expect(rotas.size).to be >= 6
  end

  rotas.each do |method, path, route|
    it "#{method} #{path} declara uma policy" do
      declarada = route.settings[:policy]

      expect(declarada).to be_present,
                           "#{method} #{path} não declara `route_setting :policy` — sem isso a " \
                           'autorização vira decisão avulsa dentro do endpoint (invariante 1)'

      classe, metodo = declarada.split('#')
      policy = classe.constantize
      expect(policy.ancestors).to include(ApplicationPolicy)
      expect(policy.new(role: nil).public_send(metodo)).to be(false),
                                                           "#{classe}##{metodo} autoriza papel NULO — a policy tem de ser fail-closed"
    end
  end

  it 'as policies negam por padrão (ApplicationPolicy é fail-closed)' do
    base = ApplicationPolicy.new(role: :owner)
    expect(base.index?).to be(false)
    expect(base.create?).to be(false)
    expect(base.update?).to be(false)
    expect(base.destroy?).to be(false)
  end

  it 'InvitationPolicy só autoriza o dono' do
    %i[index? create? destroy?].each do |acao|
      expect(InvitationPolicy.new(role: :owner).public_send(acao)).to be(true)
      expect(InvitationPolicy.new(role: :edit).public_send(acao)).to be(false)
      expect(InvitationPolicy.new(role: :view).public_send(acao)).to be(false)
    end
  end

  it 'MembershipPolicy deixa qualquer membro LER e só o dono MUTAR' do
    expect(MembershipPolicy.new(role: :view).index?).to be(true)
    expect(MembershipPolicy.new(role: :edit).index?).to be(true)
    expect(MembershipPolicy.new(role: :edit).update?).to be(false)
    expect(MembershipPolicy.new(role: :edit).destroy?).to be(false)
    expect(MembershipPolicy.new(role: :owner).update?).to be(true)
    expect(MembershipPolicy.new(role: :owner).destroy?).to be(true)
  end
end
