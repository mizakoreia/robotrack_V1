# frozen_string_literal: true

require 'rails_helper'

# invite-by-code G3.5 — lockout por convite (design D7). Testado no nível do
# SERVICE (não via HTTP) de propósito: por HTTP o rate-limit por IP (5/10min)
# barraria a 6ª tentativa com 429 ANTES de o lockout (423) aparecer. Aqui isolamos
# a mecânica do lockout; o rate-limit tem seu próprio spec.
RSpec.describe 'Lockout do código de convite', :tenancy do
  let(:owner) { create(:user, name: 'Dona Ana', email: 'ana@fabrica.com') }
  let(:ws)    { make_workspace(owner: owner, name: 'Linha 3') }
  let(:joao)  { create(:user, name: 'João Silva', email: 'joao@fabrica.com') }
  let(:owner_person) do
    in_workspace(ws) { Person.create!(name: owner.name, email: owner.email, user_id: owner.id) }
  end

  def seed_invitation(email: 'joao@fabrica.com', role: 'view')
    inv = in_workspace(ws) { Invitation.create!(email: email, role: role, created_by_person: owner_person) }
    [inv, inv.short_code]
  end

  def attempt(code, email, user: joao)
    Invitations::AcceptService.new(current_user: user, code: code, email: email).call
  ensure
    Tenant.reset_thread_context!
  end

  it 'trava o código após 5 falhas do par (código certo, e-mail errado)' do
    inv, code = seed_invitation

    5.times do
      r = attempt(code, 'errado@fabrica.com')
      expect(r[:status]).to eq(404) # genérico, não revela que existe
    end

    travado = in_workspace(ws) { Invitation.find(inv.id) }
    expect(travado.code_attempts).to eq(5)
    expect(travado.code_locked_at).to be_present

    # A 6ª, mesmo com o e-mail CORRETO, recebe 423 até a reemissão.
    r = attempt(code, 'joao@fabrica.com')
    expect(r[:status]).to eq(423)
    expect(r[:error]).to eq('invitation_code_locked')
  end


  it 'adivinhação CEGA (código inexistente) não trava linha nenhuma' do
    inv, = seed_invitation

    20.times { |i| attempt("ZZZZZZZ#{i % 10}", 'joao@fabrica.com') }

    intacto = in_workspace(ws) { Invitation.find(inv.id) }
    expect(intacto.code_attempts).to eq(0)
    expect(intacto.code_locked_at).to be_nil
  end

  it 'e-mail errado num código já travado segue genérico (não revela o 423)' do
    _inv, code = seed_invitation
    5.times { attempt(code, 'errado@fabrica.com') }

    # Par ainda inválido: 404 genérico, não 423 (o 423 é só do par que casa).
    r = attempt(code, 'outro-errado@fabrica.com')
    expect(r[:status]).to eq(404)
  end
end
