# frozen_string_literal: true

require 'rails_helper'

# Varredura de POLICIES sobre a superfície de convites e equipe
# (workspace-invitations 4.4, atualizada por authorization-policies G1 para o
# idioma singleton D3.1).
#
# Irmã das varreduras de autenticação (Onda 2) e de tenant (Onda 1), e pelo
# mesmo motivo: a garantia não pode depender de alguém lembrar. Quando o G2
# desta change entregar o mecanismo geral, este spec é substituído por
# `spec/authorization/route_sweep_spec.rb` cobrindo a superfície INTEIRA — a
# varredura só cresce, nunca encolhe.
RSpec.describe 'Varredura de policies das rotas de convite e equipe', type: :request do
  # Rotas de DOMÍNIO destas duas capacidades. Os dois caminhos por token ficam
  # de fora de propósito: não há papel a consultar (a pré-visualização é pública
  # e a autorização do aceite É a invariante 6, avaliada com a linha travada).
  SUPERFICIE = %r{^/api/v1/(invitations|memberships)}
  SEM_POLICY = [
    ['GET',  %r{^/api/v1/invitations/:token}],
    ['POST', %r{^/api/v1/invitations/:token/accept}]
  ].freeze

  # Contexto de papel arbitrário para exercitar predicados sem tocar o banco:
  # as policies só leem `context.role`.
  PAPEL = Struct.new(:role)
  CONTEXTO_NULO = PAPEL.new(nil)

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
      expect(policy.ancestors).to include(BasePolicy)
      expect(policy.public_send(metodo, CONTEXTO_NULO)).to be(false),
                                                           "#{classe}.#{metodo} autoriza papel NULO — a policy tem de ser fail-closed"
    end
  end

  it 'BasePolicy não tem predicado default — operação não declarada explode, não permite' do
    expect(BasePolicy).not_to respond_to(:index?)
    expect(BasePolicy).not_to respond_to(:create?)
    expect(BasePolicy).not_to respond_to(:update?)
    expect(BasePolicy).not_to respond_to(:destroy?)
  end

  it 'InvitationPolicy só autoriza o dono' do
    %i[index? create? destroy?].each do |acao|
      expect(InvitationPolicy.public_send(acao, PAPEL.new(:owner))).to be(true)
      expect(InvitationPolicy.public_send(acao, PAPEL.new(:edit))).to be(false)
      expect(InvitationPolicy.public_send(acao, PAPEL.new(:view))).to be(false)
    end
  end

  it 'MembershipPolicy deixa qualquer membro LER e só o dono MUTAR' do
    expect(MembershipPolicy.index?(PAPEL.new(:view))).to be(true)
    expect(MembershipPolicy.index?(PAPEL.new(:edit))).to be(true)
    expect(MembershipPolicy.update?(PAPEL.new(:edit))).to be(false)
    expect(MembershipPolicy.destroy?(PAPEL.new(:edit))).to be(false)
    expect(MembershipPolicy.update?(PAPEL.new(:owner))).to be(true)
    expect(MembershipPolicy.destroy?(PAPEL.new(:owner))).to be(true)
  end
end
