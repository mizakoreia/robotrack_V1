# frozen_string_literal: true

require 'rails_helper'

# Tarefa 1.2 / D3.3 — o contexto é a ÚNICA origem de papel, resolvido no
# servidor: dono pela coluna `workspaces.owner_user_id` (mecanismo da Onda 1),
# senão `memberships.role`. Nenhum chamador injeta papel.
RSpec.describe Authorization::Context, :tenancy do
  let(:ws) { make_workspace }
  let(:workspace) { in_workspace(ws) { Workspace.find(ws.id) } }

  it 'não aceita role por argumento — nenhum chamador pode injetá-lo (inv. 2)' do
    expect do
      described_class.new(user: ws.owner, workspace: workspace, role: :owner)
    end.to raise_error(ArgumentError)
  end

  it 'é imutável' do
    context = in_workspace(ws) { described_class.new(user: ws.owner, workspace: workspace) }
    expect(context).to be_frozen
  end

  it 'resolve o dono pela coluna owner_user_id' do
    context = in_workspace(ws) { described_class.new(user: ws.owner, workspace: workspace) }
    expect(context.role).to eq(:owner)
    expect(context.member?).to be(true)
  end

  it 'resolve membro pela linha de memberships, com a Person do workspace' do
    bruno = create(:user)
    add_member(ws, bruno, 'edit')

    context = in_workspace(ws, user: bruno) { described_class.new(user: bruno, workspace: workspace) }
    expect(context.role).to eq(:edit)
    expect(context.person).to be_present
    expect(context.person.user_id).to eq(bruno.id)
  end

  it 'usuário sem membership tem role nil e member? false' do
    diego = create(:user)
    context = in_workspace(ws) { described_class.new(user: diego, workspace: workspace) }
    expect(context.role).to be_nil
    expect(context.member?).to be(false)
  end

  it 'sem workspace, role é nil' do
    context = described_class.new(user: ws.owner, workspace: nil)
    expect(context.role).to be_nil
    expect(context.member?).to be(false)
  end
end
