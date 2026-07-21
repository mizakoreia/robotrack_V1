# frozen_string_literal: true

require 'rails_helper'

# workspace-invitations 6.5 — a suíte EXECUTÁVEL das invariantes 6 e 7 (§4.1).
#
# Este arquivo é a contribuição desta change para a suíte de
# `authorization-policies`: os seis cenários de negação obrigatórios, cada um com
# o SEU código. O critério de reprovação está escrito no primeiro exemplo — se
# dois cenários passarem a devolver o mesmo código (o clássico "422 para tudo"),
# ele falha, mesmo que cada negação individualmente continue negando. O motivo é
# de produto: sem códigos distintos, a UI não consegue dizer "peça um novo
# convite" em vez de "entre com a outra conta", e o usuário fica travado.
#
# Cada cenário afirma DUAS coisas: o código e a AUSÊNCIA de efeito colateral
# (nenhuma membership criada, convite não consumido, contagem inalterada).
RSpec.describe 'Invariantes 6 e 7, executáveis', :tenancy, type: :request do
  let(:owner)  { create(:user, name: 'Dona Ana', email: 'ana@fabrica.com') }
  let(:ws)     { make_workspace(owner: owner, name: 'Linha 3') }
  let(:joao)   { create(:user, name: 'João Silva', email: 'joao@fabrica.com') }
  let(:editor) { create(:user, name: 'Edu Edit', email: 'edu@fabrica.com') }

  let!(:pessoa_dona) do
    in_workspace(ws) { Person.create!(name: owner.name, email: owner.email, user_id: owner.id) }
  end

  def criar_convite(email: 'joao@fabrica.com', role: 'view', **attrs)
    in_workspace(ws) do
      Invitation.create!(email: email, role: role, created_by_person: pessoa_dona, **attrs)
    end
  end

  def codigo_de(response) = JSON.parse(response.body)['error']

  def estado_do_workspace
    in_workspace(ws) do
      { convites: Invitation.count, memberships: Membership.count,
        consumidos: Invitation.where.not(used_at: nil).count }
    end
  end

  # Cada cenário usa um e-mail PRÓPRIO: dois convites pendentes para o mesmo
  # e-mail no mesmo workspace são proibidos por índice único (pergunta em aberto
  # 3 do design, decidida), então reaproveitar o endereço faria os cenários
  # colidirem entre si em vez de exercitar o que devem.
  def convidado(email, nome)
    create(:user, name: nome, email: email)
  end

  # Os SEIS cenários de negação obrigatórios, na forma [nome, execução].
  def cenarios
    {
      email_divergente: lambda {
        convite = criar_convite(email: 'c1@fabrica.com')
        ana = convidado('ana.outra@fabrica.com', 'Ana Outra')
        post "/api/v1/invitations/#{convite.token}/accept", headers: auth_headers(ana)
      },
      token_usado: lambda {
        convite = criar_convite(email: 'joao@fabrica.com')
        post "/api/v1/invitations/#{convite.token}/accept", headers: auth_headers(joao)
        post "/api/v1/invitations/#{convite.token}/accept", headers: auth_headers(joao)
      },
      expirado: lambda {
        convite = criar_convite(email: 'c3@fabrica.com', expires_at: 1.day.ago)
        post "/api/v1/invitations/#{convite.token}/accept",
             headers: auth_headers(convidado('c3@fabrica.com', 'Convidado 3'))
      },
      papel_adulterado: lambda {
        convite = criar_convite(email: 'c4@fabrica.com', role: 'view')
        post "/api/v1/invitations/#{convite.token}/accept",
             params: { role: 'edit' }, headers: auth_headers(convidado('c4@fabrica.com', 'Convidado 4'))
      },
      workspace_alheio: lambda {
        convite = criar_convite(email: 'c5@fabrica.com')
        outro = make_workspace(owner: create(:user, email: 'dono.b@fabrica.com'), name: 'Linha 9')
        post "/api/v1/invitations/#{convite.token}/accept",
             headers: auth_headers(convidado('c5@fabrica.com', 'Convidado 5')).merge('X-Workspace-Id' => outro.id)
      },
      edit_convidando: lambda {
        add_member(ws, editor, 'edit')
        post '/api/v1/invitations', params: { email: 'terceiro@fabrica.com', role: 'view' },
                                    headers: auth_headers(editor).merge('X-Workspace-Id' => ws.id)
      }
    }
  end

  it 'os seis cenários falham cada um com um código DISTINTO' do
    codigos = cenarios.transform_values do |cenario|
      cenario.call
      [response.status, codigo_de(response)]
    end

    expect(codigos[:email_divergente]).to eq([403, 'invitation_email_mismatch'])
    expect(codigos[:token_usado]).to eq([409, 'invitation_already_used'])
    expect(codigos[:expirado]).to eq([410, 'invitation_expired'])
    expect(codigos[:papel_adulterado]).to eq([422, 'unexpected_parameter'])
    expect(codigos[:workspace_alheio]).to eq([422, 'invitation_workspace_mismatch'])
    expect(codigos[:edit_convidando]).to eq([403, 'forbidden'])

    # O critério de reprovação: um código genérico para todos passa nos exemplos
    # individuais e falha AQUI.
    apenas_codigos = codigos.values.map(&:last)
    expect(apenas_codigos.uniq.size).to eq(apenas_codigos.size),
                                        "códigos repetidos entre cenários de negação: #{apenas_codigos.tally.select { |_, n| n > 1 }}"
  end

  describe 'invariante 6 — nenhuma negação deixa efeito colateral' do
    it 'e-mail divergente não consome nem cria membership' do
      convite = criar_convite
      ana = create(:user, name: 'Ana Outra', email: 'ana.outra@fabrica.com')

      expect { post "/api/v1/invitations/#{convite.token}/accept", headers: auth_headers(ana) }
        .not_to(change { estado_do_workspace })

      expect(codigo_de(response)).to eq('invitation_email_mismatch')
    end

    it 'expirado não consome nem cria membership' do
      convite = criar_convite(expires_at: 1.day.ago)

      expect { post "/api/v1/invitations/#{convite.token}/accept", headers: auth_headers(joao) }
        .not_to(change { estado_do_workspace })
    end

    it 'papel adulterado não consome nem cria membership' do
      convite = criar_convite(role: 'view')

      expect do
        post "/api/v1/invitations/#{convite.token}/accept",
             params: { role: 'edit' }, headers: auth_headers(joao)
      end.not_to(change { estado_do_workspace })
    end

    it 'aceite repetido não cria a SEGUNDA membership' do
      convite = criar_convite
      post "/api/v1/invitations/#{convite.token}/accept", headers: auth_headers(joao)
      depois_do_primeiro = estado_do_workspace

      3.times { post "/api/v1/invitations/#{convite.token}/accept", headers: auth_headers(joao) }

      expect(estado_do_workspace).to eq(depois_do_primeiro)
      expect(depois_do_primeiro[:memberships]).to eq(1)
    end
  end

  describe 'invariante 7 — o convite é sempre do workspace do criador' do
    it 'o papel `owner` não é representável nem pela API nem pelo banco' do
      post '/api/v1/invitations', params: { email: 'x@fabrica.com', role: 'owner' },
                                  headers: auth_headers(owner).merge('X-Workspace-Id' => ws.id)
      expect(codigo_de(response)).to eq('invalid_role')

      expect do
        in_workspace(ws) do
          conn = ActiveRecord::Base.connection
          conn.execute(<<~SQL)
            INSERT INTO invitations (workspace_id, token, email, role, created_by_person_id, expires_at)
            VALUES (#{conn.quote(ws.id)}, 'rt_inv_forjado', 'x@fabrica.com', 'owner',
                    #{conn.quote(pessoa_dona.id)}, now() + interval '7 days')
          SQL
        end
      end.to raise_error(ActiveRecord::StatementInvalid, /invalid input value for enum/)
    end

    it 'o criador é sempre do workspace do convite (FK composta)' do
      outro_dono = create(:user, email: 'dono.b@fabrica.com')
      ws_b = make_workspace(owner: outro_dono, name: 'Linha 9')
      pessoa_b = in_workspace(ws_b, user: outro_dono) do
        Person.create!(name: 'Dono B', email: outro_dono.email, user_id: outro_dono.id)
      end

      expect do
        in_workspace(ws) do
          Invitation.create!(email: 'x@fabrica.com', role: 'view', created_by_person_id: pessoa_b.id)
        end
      end.to raise_error(ActiveRecord::InvalidForeignKey, /fk_invitations_creator_in_workspace/)
    end

    it 'o papel da membership vem do convite, não do cliente' do
      convite = criar_convite(role: 'view')

      post "/api/v1/invitations/#{convite.token}/accept", headers: auth_headers(joao)

      expect(in_workspace(ws) { Membership.find_by(user_id: joao.id) }.role).to eq('view')
    end
  end
end
