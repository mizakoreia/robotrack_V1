# frozen_string_literal: true

require 'rails_helper'

# workspace-invitations 6.2 / D-INV-9 — expurgo de convites expirados.
#
# Três propriedades, e as duas últimas são as que impedem estrago:
#   1. o pendente expirado há mais de 30 dias some;
#   2. o pendente expirado há POUCO sobrevive — para o clique num link velho
#      produzir `410 invitation_expired` ("peça outro") em vez de `404`
#      ("confira o link"), enquanto o link ainda circula;
#   3. o CONSUMIDO nunca some, por mais antigo que seja — ele é a prova auditável
#      do acesso, e a FK da membership o protege com ON DELETE RESTRICT.
RSpec.describe Invitations::PurgeExpiredJob, :tenancy do
  let(:owner) { create(:user, name: 'Dona Ana', email: 'ana@fabrica.com') }
  let(:ws)    { make_workspace(owner: owner, name: 'Linha 3') }
  let(:guest) { create(:user, name: 'João Silva', email: 'joao@fabrica.com') }
  let(:pessoa_dona) do
    in_workspace(ws) { Person.create!(name: owner.name, email: owner.email, user_id: owner.id) }
  end

  def criar_convite(email:, expires_at:, used: false)
    in_workspace(ws) do
      convite = Invitation.create!(email: email, role: 'view', created_by_person: pessoa_dona,
                                   expires_at: expires_at)
      if used
        pessoa = Person.create!(name: "P #{email}", email: "p-#{email}", user_id: nil)
        Membership.create!(workspace_id: ws.id, user: guest, person: pessoa, role: 'view',
                           invitation: convite)
        convite.update!(used_at: Time.current, used_by_user_id: guest.id)
      end
      convite
    end
  end

  def existe?(convite)
    in_workspace(ws) { Invitation.exists?(id: convite.id) }
  end

  it 'apaga o convite pendente expirado há 31 dias' do
    velho = criar_convite(email: 'velho@fabrica.com', expires_at: 31.days.ago)

    expect(described_class.new.perform).to eq(1)
    expect(existe?(velho)).to be(false)
  end

  it 'PRESERVA o convite expirado há 3 dias (mensagem útil vale mais que a linha)' do
    recente = criar_convite(email: 'recente@fabrica.com', expires_at: 3.days.ago)

    described_class.new.perform

    expect(existe?(recente)).to be(true)
  end

  it 'PRESERVA convite consumido, por mais antigo que seja' do
    antigo = criar_convite(email: 'antigo@fabrica.com', expires_at: 2.years.ago, used: true)

    expect(described_class.new.perform).to eq(0)
    expect(existe?(antigo)).to be(true)
  end

  it 'PRESERVA convite pendente ainda vigente' do
    vigente = criar_convite(email: 'vigente@fabrica.com', expires_at: 3.days.from_now)

    described_class.new.perform

    expect(existe?(vigente)).to be(true)
  end

  it 'roda sem workspace corrente (é manutenção global) e atravessa workspaces' do
    outro_dono = create(:user, email: 'dono.b@fabrica.com')
    ws_b = make_workspace(owner: outro_dono, name: 'Linha 9')
    pessoa_b = in_workspace(ws_b, user: outro_dono) do
      Person.create!(name: 'Dono B', email: outro_dono.email, user_id: outro_dono.id)
    end
    convite_b = in_workspace(ws_b, user: outro_dono) do
      Invitation.create!(email: 'alheio@fabrica.com', role: 'view', created_by_person: pessoa_b,
                         expires_at: 40.days.ago)
    end
    convite_a = criar_convite(email: 'velho.a@fabrica.com', expires_at: 40.days.ago)

    # Nenhum contexto de tenant aberto aqui — é assim que o Sidekiq o executa.
    expect(Tenant.current_workspace_id).to be_nil
    expect(described_class.new.perform).to eq(2)

    expect(existe?(convite_a)).to be(false)
    expect(in_workspace(ws_b, user: outro_dono) { Invitation.exists?(id: convite_b.id) }).to be(false)
  end

  it 'a política de expurgo NÃO abre leitura de convite vivo, nem com a flag ligada' do
    vivo = criar_convite(email: 'vivo@fabrica.com', expires_at: 3.days.from_now)

    # Mesmo quem setasse a variável à mão só alcança linhas já marcadas para
    # morrer: não usadas E expiradas há mais de 30 dias.
    linhas = ActiveRecord::Base.transaction do
      conn = ActiveRecord::Base.connection
      conn.execute("SELECT set_config('app.invitation_purge', 'on', true)")
      conn.select_values('SELECT token FROM invitations')
    end

    expect(linhas).to be_empty
    expect(existe?(vivo)).to be(true)
  end

  it 'está declarado no agendamento (senão ninguém o executa em produção)' do
    agenda = YAML.load_file(Rails.root.join('config/sidekiq_cron.yml'))

    expect(agenda.dig('purge_expired_invitations', 'class')).to eq('Invitations::PurgeExpiredJob')
    expect(agenda.dig('purge_expired_invitations', 'cron')).to be_present
  end
end
