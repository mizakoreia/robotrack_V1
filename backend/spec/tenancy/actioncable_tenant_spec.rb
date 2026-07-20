# frozen_string_literal: true

require 'rails_helper'

# Canal de teste — definido AQUI (spec/), não em app/channels/, para não violar a
# guarda de "só dois arquivos de canal" do connection_spec.
class TenancyProbeChannel < ApplicationCable::Channel
  def subscribed
    resolution = resolve_workspace_or_reject(params[:workspace_id])
    stream_from "ws:#{resolution.workspace_id}" if resolution
  end
end

# tenant-isolation / D-6 (tarefa 4.4): contexto de tenant no ActionCable.
RSpec.describe TenancyProbeChannel, :tenancy, type: :channel do
  let(:owner) { create(:user) }
  let(:ws) { make_workspace(owner: owner) }

  it 'aceita a subscrição do dono ao próprio workspace' do
    stub_connection current_user: owner
    subscribe(workspace_id: ws.id)

    expect(subscription).to be_confirmed
    expect(subscription).to have_stream_from("ws:#{ws.id}")
  end

  it 'rejeita subscrição a workspace alheio (não membro)' do
    outra = make_workspace
    stub_connection current_user: owner
    subscribe(workspace_id: outra.id)

    expect(subscription).to be_rejected
  end

  it 'rejeita subscrição sem workspace_id' do
    stub_connection current_user: owner
    subscribe(workspace_id: nil)

    expect(subscription).to be_rejected
  end
end
