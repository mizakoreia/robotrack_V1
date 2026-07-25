# frozen_string_literal: true

require 'rails_helper'
require 'rake'

# code-only-invites (DA-1) — a reemissão de código dos convites pendentes.
# Prova que um convite pendente que só tinha o LINK (código antigo perdido)
# recebe um CÓDIGO NOVO recuperável, impresso para o dono repassar.
RSpec.describe 'rake invitations:reissue_codes', :tenancy do
  let(:owner) { create(:user, name: 'Dona Ana', email: 'ana@fabrica.com') }
  let(:ws)    { make_workspace(owner: owner, name: 'Linha 3') }
  let(:owner_person) do
    in_workspace(ws) { Person.create!(name: owner.name, email: owner.email, user_id: owner.id) }
  end

  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?('invitations:reissue_codes')
  end

  def run_reissue(workspace_id)
    task = Rake::Task['invitations:reissue_codes']
    task.reenable
    out = StringIO.new
    orig = $stdout
    $stdout = out
    task.invoke(workspace_id)
    out.string
  ensure
    $stdout = orig
  end

  it 'reemite um código novo, renova a validade, zera o lockout e imprime o par' do
    inv = in_workspace(ws) do
      Invitation.create!(email: 'joao@fabrica.com', role: 'edit', created_by_person: owner_person)
    end
    # Simula um convite pendente "antigo": código travado e prestes a expirar.
    in_workspace(ws) do
      Invitation.where(id: inv.id).update_all(
        code_locked_at: Time.current, code_attempts: 5, code_expires_at: 1.minute.from_now
      )
    end
    hash_antigo = in_workspace(ws) { Invitation.find(inv.id).code_hash }

    saida = run_reissue(ws.id)

    recarregado = in_workspace(ws) { Invitation.find(inv.id) }
    expect(recarregado.code_hash).to be_present
    expect(recarregado.code_hash).not_to eq(hash_antigo)     # código NOVO
    expect(recarregado.code_locked_at).to be_nil             # lockout zerado
    expect(recarregado.code_attempts).to eq(0)
    expect(recarregado.code_expires_at).to be > 40.hours.from_now # ~48h de validade

    # Imprime o e-mail e um código formatado XXXX-XXXX, sem enviar nada.
    expect(saida).to include('joao@fabrica.com')
    expect(saida).to match(/[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}/)
  end

  it 'não toca em convites já consumidos nem expirados' do
    usado = in_workspace(ws) do
      i = Invitation.create!(email: 'usado@fabrica.com', role: 'view', created_by_person: owner_person)
      Invitation.where(id: i.id).update_all(used_at: Time.current, used_by_user_id: owner.id)
      i
    end
    expirado = in_workspace(ws) do
      i = Invitation.create!(email: 'exp@fabrica.com', role: 'view', created_by_person: owner_person)
      Invitation.where(id: i.id).update_all(expires_at: 2.days.ago)
      i
    end
    hash_usado = in_workspace(ws) { Invitation.find(usado.id).code_hash }
    hash_exp   = in_workspace(ws) { Invitation.find(expirado.id).code_hash }

    run_reissue(ws.id)

    expect(in_workspace(ws) { Invitation.find(usado.id).code_hash }).to eq(hash_usado)
    expect(in_workspace(ws) { Invitation.find(expirado.id).code_hash }).to eq(hash_exp)
  end
end
