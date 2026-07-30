# frozen_string_literal: true

require 'rails_helper'

# send-feedback — a API do canal de feedback do beta. Enviar é de qualquer membro;
# ler a caixa é do dono. O `workspace_id` vem do contexto (nunca do corpo) e o
# `user_id` do bearer; um workspace não vê o feedback de outro (RLS).
RSpec.describe 'send-feedback — /api/v1/feedbacks', :tenancy, type: :request do
  let(:owner) { create(:user, name: 'Ana Dona') }
  let(:ws)    { make_workspace(owner: owner) }

  def headers(user) = auth_headers(user).merge('X-Workspace-Id' => ws.id)

  describe 'POST — enviar feedback' do
    it 'qualquer membro (owner/edit/view) envia; grava workspace e autor' do
      leitor = create(:user, name: 'Léo'); add_member(ws, leitor, 'view')

      post '/api/v1/feedbacks',
           params: { message: 'O botão de avançar some no celular', context: { route: '/robo/42', role: 'view' } },
           headers: headers(leitor)

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body['message']).to eq('O botão de avançar some no celular')
      expect(body['context']).to eq('route' => '/robo/42', 'role' => 'view')
      expect(body['submitter']).to eq('name' => 'Léo', 'email' => leitor.email)

      in_workspace(ws) do
        row = Feedback.last
        expect(row.workspace_id).to eq(ws.id)
        expect(row.user_id).to eq(leitor.id)
        expect(row.message).to eq('O botão de avançar some no celular')
      end
    end

    it 'o dono também envia' do
      post '/api/v1/feedbacks', params: { message: 'Sugestão do dono' }, headers: headers(owner)
      expect(response).to have_http_status(:created)
    end

    it 'mensagem em branco é recusada (validação de parâmetro)' do
      post '/api/v1/feedbacks', params: { message: '   ' }, headers: headers(owner)
      expect(response.status).to be_in([400, 422])
      in_workspace(ws) { expect(Feedback.count).to eq(0) }
    end

    it 'context não vem do corpo para o workspace_id: a linha cai no workspace do header' do
      outro = make_workspace(owner: create(:user))
      # mesmo que o cliente tente forjar, não há coluna workspace_id no corpo aceito;
      # a linha nasce no workspace do contexto (o do header).
      post '/api/v1/feedbacks',
           params: { message: 'x', context: { workspace_id: outro.id } },
           headers: headers(owner)
      expect(response).to have_http_status(:created)
      in_workspace(ws)    { expect(Feedback.count).to eq(1) }
      in_workspace(outro) { expect(Feedback.count).to eq(0) }
    end

    it 'não-membro é barrado (403/404), sem gravar' do
      estranho = create(:user, name: 'Estranho')
      post '/api/v1/feedbacks', params: { message: 'invasão' }, headers: headers(estranho)
      expect(response.status).to be_in([403, 404])
      in_workspace(ws) { expect(Feedback.count).to eq(0) }
    end
  end

  describe 'GET — a caixa do dono' do
    it 'o dono lê os feedbacks do workspace, mais recentes primeiro' do
      leitor = create(:user, name: 'Léo'); add_member(ws, leitor, 'view')
      post '/api/v1/feedbacks', params: { message: 'primeiro' }, headers: headers(leitor)
      post '/api/v1/feedbacks', params: { message: 'segundo' }, headers: headers(owner)

      get '/api/v1/feedbacks', headers: headers(owner)
      expect(response).to have_http_status(:ok)
      msgs = JSON.parse(response.body).map { |f| f['message'] }
      expect(msgs).to eq(%w[segundo primeiro])
    end

    it 'editor e visualizador NÃO leem a caixa (403 — owner-only)' do
      editor = create(:user, name: 'Edu'); add_member(ws, editor, 'edit')
      leitor = create(:user, name: 'Léo'); add_member(ws, leitor, 'view')

      get '/api/v1/feedbacks', headers: headers(editor)
      expect(response).to have_http_status(:forbidden)
      get '/api/v1/feedbacks', headers: headers(leitor)
      expect(response).to have_http_status(:forbidden)
    end

    it 'não vê o feedback de outro workspace (RLS)' do
      dono_b = create(:user, name: 'Bia')
      ws_b   = make_workspace(owner: dono_b)
      post '/api/v1/feedbacks', params: { message: 'do outro ws' },
           headers: auth_headers(dono_b).merge('X-Workspace-Id' => ws_b.id)

      get '/api/v1/feedbacks', headers: headers(owner)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq([])
    end
  end
end
