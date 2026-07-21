# frozen_string_literal: true

require 'rails_helper'

# authorization-policies G4 (tarefas 4.1–4.4 / D3.6, D3.10) — varredura NEGATIVA
# de vazamento entre tenants, GERADA da tabela de rotas, não escrita à mão.
#
# Para toda rota cujo path tem `:id`/`:*_id`, um exemplo autentica como o dono
# do workspace B e endereça um recurso semeado no workspace A, exigindo `404`
# com corpo BYTE-A-BYTE igual ao de um UUID aleatório (D3.6 — 403 confirmaria
# existência). Rota que o gerador não cobre precisa de entrada em
# `config/authorization/cross_tenant_overrides.yml`; sem gerador E sem override,
# o spec falha nomeando a rota — um endpoint novo herda o teste negativo
# automaticamente.
RSpec.describe 'Varredura negativa de vazamento entre tenants', :tenancy, type: :request do
  OVERRIDES = YAML.safe_load_file(
    Rails.root.join('config/authorization/cross_tenant_overrides.yml')
  ).map { |e| [e['method'], e['path']] }

  # Rotas elegíveis: qualquer segmento :id ou :*_id (mas não :token/:version).
  ELEGIVEIS = Api::Root.routes.filter_map do |route|
    path = route.path.sub(/\(\.:format\)\z/, '').sub('/:version', '/v1')
    method = route.request_method.to_s.upcase
    next if method == 'HEAD'
    next unless path.match?(%r{/:(\w+_)?id(/|\z)})

    [method, path]
  end.uniq

  # Geradores: como semear o recurso em WS-A e montar a requisição do Diego
  # (dono de WS-B). Cada lambda devolve [path_concreto, params].
  GERADORES = {
    'DELETE /api/v1/invitations/:id' => ->(ids) { ["/api/v1/invitations/#{ids[:invitation]}", {}] },
    'PATCH /api/v1/memberships/:id' => ->(ids) { ["/api/v1/memberships/#{ids[:membership]}", { role: 'edit' }] },
    'DELETE /api/v1/memberships/:id' => ->(ids) { ["/api/v1/memberships/#{ids[:membership]}", {}] },
    # commissioning-hierarchy G3: os endpoints novos nascem DENTRO da varredura.
    'PATCH /api/v1/projects/:id' => ->(ids) { ["/api/v1/projects/#{ids[:project]}", { name: 'X', lock_version: 0 }] },
    'DELETE /api/v1/projects/:id' => ->(ids) { ["/api/v1/projects/#{ids[:project]}", {}] },
    'PATCH /api/v1/cells/:id' => ->(ids) { ["/api/v1/cells/#{ids[:cell]}", { name: 'X', lock_version: 0 }] },
    'DELETE /api/v1/cells/:id' => ->(ids) { ["/api/v1/cells/#{ids[:cell]}", {}] },
    'PATCH /api/v1/robots/:id' => ->(ids) { ["/api/v1/robots/#{ids[:robot]}", { name: 'X', lock_version: 0 }] },
    'DELETE /api/v1/robots/:id' => ->(ids) { ["/api/v1/robots/#{ids[:robot]}", {}] }
  }.freeze

  it 'toda rota com id tem gerador OU override — e nenhum órfão' do
    ELEGIVEIS.each do |method, path|
      chave = "#{method} #{path}"
      coberta = GERADORES.key?(chave) || OVERRIDES.include?([method, path])
      expect(coberta).to be(true),
                         "#{chave} recebe id de recurso e não tem gerador nem override — " \
                         'sem prova negativa de cross-tenant (D3.10)'
    end

    orfaos = OVERRIDES.reject { |m, p| ELEGIVEIS.include?([m, p]) }
    expect(orfaos).to be_empty, "overrides órfãos (rota não existe mais): #{orfaos.inspect}"

    expect(ELEGIVEIS.size).to eq(GERADORES.size + OVERRIDES.size),
                              'contagem de rotas elegíveis não bate com geradores + overrides'
  end

  describe 'os exemplos gerados' do
    let(:ana)   { create(:user, name: 'Ana Dona A') }
    let(:diego) { create(:user, name: 'Diego Dono B') }
    let(:ws_a)  { make_workspace(owner: ana, name: 'WS-A') }
    let(:ws_b)  { make_workspace(owner: diego, name: 'WS-B') }

    let(:ids) do
      bruno = create(:user, name: 'Bruno Edit A')
      add_member(ws_a, bruno, 'edit')
      membership_id = in_workspace(ws_a) { Membership.find_by(user_id: bruno.id).id }
      invitation_id = in_workspace(ws_a) do
        pessoa_ana = Person.create!(name: ana.name, email: ana.email, user_id: ana.id)
        Invitation.create!(
          workspace_id: ws_a.id,
          email: 'convidada@ex.com',
          role: 'edit',
          token: "rt_inv_#{SecureRandom.urlsafe_base64(32)}",
          created_by_person_id: pessoa_ana.id
        ).id
      end
      hierarquia = in_workspace(ws_a) do
        projeto = Project.create!(name: 'P de A')
        celula = Cell.create!(project_id: projeto.id, name: 'C de A')
        robo = Robot.create!(cell_id: celula.id, name: 'R de A')
        { project: projeto.id, cell: celula.id, robot: robo.id }
      end

      { membership: membership_id, invitation: invitation_id }.merge(hierarquia)
    end

    def headers_diego
      auth_headers(diego).merge('X-Workspace-Id' => ws_b.id)
    end

    GERADORES.each do |chave, gerador|
      it "#{chave} com id de WS-A responde 404 byte-a-byte igual a id inexistente" do
        method, = chave.split(' ')
        path_real, params = gerador.call(ids)
        path_fake = path_real.sub(%r{[^/]+\z}, SecureRandom.uuid)

        send(method.downcase, path_real, params: params, headers: headers_diego)
        status_real = response.status
        corpo_real = response.body

        send(method.downcase, path_fake, params: params, headers: headers_diego)

        expect(status_real).to eq(404), "#{chave}: esperado 404 para recurso de outro tenant, veio #{status_real}"
        expect(response.status).to eq(404)
        expect(corpo_real).to eq(response.body),
                              "#{chave}: corpo do 404 cross-tenant difere do 404 de id inexistente — vazamento por distinção"
      end
    end

    it 'a RLS SOZINHA ainda nega, com a avaliação de policy desligada (4.3)' do
      # Neutraliza o gate SÓ neste exemplo (o stub morre com ele): se alguém
      # remover a RLS confiando na policy, este é o teste que vermelha.
      allow_any_instance_of(Grape::Endpoint).to receive(:authorize_route!)

      path, params = GERADORES['DELETE /api/v1/invitations/:id'].call(ids)
      delete path, params: params, headers: headers_diego

      expect(response).to have_http_status(:not_found)
      expect(in_workspace(ws_a) { Invitation.count }).to eq(1)
    end

    it 'X-Total-Count reflete só o tenant corrente (4.4)' do
      ids # semeia WS-A: bruno como membro (o dono não tem linha)
      clara = create(:user, name: 'Clara View A')
      add_member(ws_a, clara, 'view')

      get '/api/v1/memberships', headers: headers_diego
      expect(response).to have_http_status(:ok)
      expect(response.headers['X-Total-Count']).to eq('1') # só o dono de WS-B

      get '/api/v1/memberships', headers: auth_headers(ana).merge('X-Workspace-Id' => ws_a.id)
      expect(response.headers['X-Total-Count']).to eq('3') # dona + bruno + clara
    end
  end
end
