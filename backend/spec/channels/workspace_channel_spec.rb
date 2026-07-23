# frozen_string_literal: true

require 'rails_helper'

# realtime-collaboration 2.3 — os 4 cenários de "Autorização de assinatura do
# WorkspaceChannel pela membership". A decisão é NO BANCO, no `subscribed`, e não
# olha nada enviado pelo cliente: membro assina o próprio workspace; membro de
# outro workspace é rejeitado (o negativo cross-tenant é obrigatório — nenhum byte
# de W1 pode chegar a um não-membro); um workspace inexistente dá a MESMA
# rejeição, indistinguível; e o papel `view` assina normalmente (o canal
# transporta ponteiro, a leitura fina é das policies).
RSpec.describe WorkspaceChannel, :tenancy, type: :channel do
  let(:owner) { create(:user, name: 'Ana Dona') }
  let(:w1) { make_workspace(owner: owner) }

  it 'aceita a assinatura de um membro edit ao próprio workspace e abre o stream v1' do
    editor = create(:user, name: 'Edu Edit')
    add_member(w1, editor, 'edit')
    stub_connection current_user: editor

    subscribe(workspace_id: w1.id)

    expect(subscription).to be_confirmed
    expect(subscription).to have_stream_from("ws:#{w1.id}:v1")
  end

  it 'aceita a assinatura do papel view (transporta ponteiro, leitura é das policies)' do
    viewer = create(:user, name: 'Vera View')
    add_member(w1, viewer, 'view')
    stub_connection current_user: viewer

    subscribe(workspace_id: w1.id)

    expect(subscription).to be_confirmed
    expect(subscription).to have_stream_from("ws:#{w1.id}:v1")
  end

  it 'rejeita membro de OUTRO workspace assinando W1 — nenhum stream de W1 é aberto' do
    w2 = make_workspace(owner: create(:user, name: 'Bruno'))
    intruso = create(:user, name: 'Ivo Intruso')
    add_member(w2, intruso, 'edit')
    stub_connection current_user: intruso

    subscribe(workspace_id: w1.id)

    # Assinatura rejeitada não abre stream algum — por isso a ausência de `ws:W1`
    # está provada pelo próprio `be_rejected` (inspecionar streams de uma
    # assinatura rejeitada levanta "Must be subscribed!").
    expect(subscription).to be_rejected
  end

  it 'rejeita workspace inexistente com a mesma resposta do não-membro (indistinguível)' do
    forasteiro = create(:user, name: 'Ora Fora')
    stub_connection current_user: forasteiro

    subscribe(workspace_id: SecureRandom.uuid)

    expect(subscription).to be_rejected
  end

  # realtime-collaboration 8.2/8.3 (§Req. revogação) — a reverificação na entrega.
  # A decisão foi extraída em `delivery_decision` (o bloco do `stream_from` só a
  # aplica), então os 5 cenários testam a decisão direto.
  describe 'revogação viva no ponto de entrega (8.3)' do
    let(:cida) { create(:user, name: 'Cida') }

    def envelope(type, user_id: nil)
      { 'type' => type, 'entity' => { 'kind' => 'membership', 'user_id' => user_id } }
    end

    it 'membro autorizado: entrega qualquer envelope' do
      add_member(w1, cida, 'edit')
      stub_connection current_user: cida
      subscribe(workspace_id: w1.id)

      expect(subscription.send(:delivery_decision, w1.id, envelope('task.updated'))).to eq(:transmit)
    end

    it 'membro revogado: a PRÓPRIA membership.revoked é entregue e encerra o stream' do
      membership = add_member(w1, cida, 'edit')
      stub_connection current_user: cida
      subscribe(workspace_id: w1.id)
      in_workspace(w1) { membership.destroy! }

      decision = subscription.send(:delivery_decision, w1.id, envelope('membership.revoked', user_id: cida.id))
      expect(decision).to eq(:self_revoke)
    end

    it 'membro revogado: envelope POSTERIOR (não a própria revogação) é descartado' do
      membership = add_member(w1, cida, 'edit')
      stub_connection current_user: cida
      subscribe(workspace_id: w1.id)
      in_workspace(w1) { membership.destroy! }

      expect(subscription.send(:delivery_decision, w1.id, envelope('task.updated'))).to eq(:stop)
    end

    it 'revogação de OUTRO membro (D) não expulsa C — C segue autorizado e recebe' do
      add_member(w1, cida, 'edit')
      dora = create(:user, name: 'Dora')
      add_member(w1, dora, 'edit')
      stub_connection current_user: cida
      subscribe(workspace_id: w1.id)

      decision = subscription.send(:delivery_decision, w1.id, envelope('membership.revoked', user_id: dora.id))
      expect(decision).to eq(:transmit) # C ainda é membro → entrega (e o cliente invalida members/people)
    end
  end
end
