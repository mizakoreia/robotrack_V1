# frozen_string_literal: true

require 'rails_helper'

# commissioning-hierarchy 5.1–5.4 (§2.9, D-H3, D-H4) — reordenação em lote.
RSpec.describe 'Reordenação da hierarquia', :tenancy, type: :request do
  let(:ana)   { create(:user, name: 'Ana Dona') }
  let(:ws)    { make_workspace(owner: ana) }
  let(:clara) { create(:user, name: 'Clara View') }
  let(:diego) { create(:user, name: 'Diego De B') }
  let(:ws_b)  { make_workspace(owner: diego) }

  def headers(user, workspace = ws)
    auth_headers(user).merge('X-Workspace-Id' => workspace.id)
  end

  def seed_projetos(nomes)
    in_workspace(ws) { nomes.map { |n| Project.create!(name: n) } }
  end

  it 'renumera 0..n-1 na ordem enviada e devolve a lista final' do
    p0, p1, p2 = seed_projetos(%w[A B C])

    patch '/api/v1/projects/reorder',
          params: { scope_id: ws.id, ordered_ids: [p2.id, p0.id, p1.id] },
          headers: headers(ana)

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body).map { |p| [p['name'], p['position']] })
      .to eq([['C', 0], ['A', 1], ['B', 2]])
  end

  it 'conjunto divergente (irmão criado depois do carregamento): 409 com o conjunto atual, sem escrita' do
    p0, p1, = seed_projetos(%w[A B])
    ordem_carregada = [p1.id, p0.id]
    novo = in_workspace(ws) { Project.create!(name: 'C nova') }

    patch '/api/v1/projects/reorder',
          params: { scope_id: ws.id, ordered_ids: ordem_carregada },
          headers: headers(ana)

    expect(response).to have_http_status(:conflict)
    corpo = JSON.parse(response.body)
    expect(corpo['error']).to eq('reorder_conflict')
    expect(corpo['details']['current_ids']).to contain_exactly(p0.id, p1.id, novo.id)

    posicoes = in_workspace(ws) { Project.order(:position).pluck(:name, :position) }
    expect(posicoes).to eq([['A', 0], ['B', 1], ['C nova', 2]])
  end

  it 'ordered_ids com duplicata também é 409 — nunca posição duplicada nem buraco' do
    p0, p1, = seed_projetos(%w[A B])

    patch '/api/v1/projects/reorder',
          params: { scope_id: ws.id, ordered_ids: [p0.id, p0.id, p1.id] },
          headers: headers(ana)

    expect(response).to have_http_status(:conflict)
  end

  it 'scope_id divergente do workspace da sessão é 422 (decisão 7)' do
    seed_projetos(%w[A])
    patch '/api/v1/projects/reorder',
          params: { scope_id: ws_b.id, ordered_ids: [SecureRandom.uuid] },
          headers: headers(ana)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(JSON.parse(response.body)['error']).to eq('scope_mismatch')
  end

  it 'view não reordena (403) e PATCH de item não aceita position' do
    p0, p1, = seed_projetos(%w[A B])
    add_member(ws, clara, 'view')

    patch '/api/v1/projects/reorder',
          params: { scope_id: ws.id, ordered_ids: [p1.id, p0.id] },
          headers: headers(clara)
    expect(response).to have_http_status(:forbidden)

    # `position` nem é param declarado: enviar não move (Grape ignora o extra).
    patch "/api/v1/projects/#{p1.id}",
          params: { name: 'B', lock_version: 0, position: 0 },
          headers: headers(ana)
    expect(in_workspace(ws) { Project.find(p1.id).position }).to eq(1)
  end

  it 'reordenar células de projeto de OUTRO workspace é 404' do
    projeto = in_workspace(ws) { Project.create!(name: 'De A') }
    celula = in_workspace(ws) { Cell.create!(project_id: projeto.id, name: 'C') }

    patch '/api/v1/cells/reorder',
          params: { scope_id: projeto.id, ordered_ids: [celula.id] },
          headers: headers(diego, ws_b)

    expect(response).to have_http_status(:not_found)
  end

  it 'reordenar NÃO incrementa lock_version; renome com lock antigo continua válido (D-H9)' do
    p0, p1, = seed_projetos(%w[A B])
    lock_antes = in_workspace(ws) { Project.find(p0.id).lock_version }

    patch '/api/v1/projects/reorder',
          params: { scope_id: ws.id, ordered_ids: [p1.id, p0.id] },
          headers: headers(ana)
    expect(response).to have_http_status(:ok)

    expect(in_workspace(ws) { Project.find(p0.id).lock_version }).to eq(lock_antes)

    patch "/api/v1/projects/#{p0.id}",
          params: { name: 'A renomeada', lock_version: lock_antes },
          headers: headers(ana)
    expect(response).to have_http_status(:ok)
  end

  it 'duas reordenações concorrentes do mesmo escopo: sem deadlock, posições contíguas (5.4)' do
    projeto = in_workspace(ws) { Project.create!(name: 'Concorrência') }
    celulas = in_workspace(ws) { 4.times.map { |i| Cell.create!(project_id: projeto.id, name: "C#{i}") } }
    ids = celulas.map(&:id)

    ordens = [ids.shuffle, ids.shuffle]
    resultados = ordens.map do |ordem|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          Tenant.with(workspace_id: ws.id, user_id: ana.id) do
            Hierarchy::ReorderService.new(model: Cell).call(scope_id: projeto.id, ordered_ids: ordem)
          end
        end
      end
    end.map(&:value)

    expect(resultados.map { |r| r[:status] }).to all(eq(200))
    posicoes = in_workspace(ws) { Cell.where(project_id: projeto.id).order(:position).pluck(:position) }
    expect(posicoes).to eq([0, 1, 2, 3])
  end
end
