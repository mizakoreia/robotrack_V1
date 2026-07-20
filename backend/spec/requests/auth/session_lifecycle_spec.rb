# frozen_string_literal: true

require 'rails_helper'

# identity-and-auth: login, TTL, logout/denylist, renovação e payload
# (tarefas 2.3, 2.4, 2.6, 4.5). A falha a caçar em 2.6 é logout responder 204 com
# o token ainda passando em GET /auth/v1/me — por isso o ciclo é exercitado
# ponta a ponta com tokens REAIS despachados pelo mesmo caminho do endpoint.
RSpec.describe 'Ciclo de vida da sessão', type: :request do
  def json = JSON.parse(response.body)

  def decode(token, verify_exp: false)
    JWT.decode(token, ::Auth::TokenService.secret, true, algorithm: 'HS256', verify_expiration: verify_exp).first
  end

  def login(email:, password:, remember_me: false)
    post '/auth/v1/session', params: { email: email, password: password, remember_me: remember_me }
    json.dig('data', 'access_token')
  end

  let!(:ana) { create(:user, :with_password, name: 'Ana Souza', email: 'ana@fabrica.com', password: 'senha123') }

  # ---- Login ---------------------------------------------------------------
  describe 'POST /auth/v1/session' do
    it 'autentica com credenciais corretas: 200, token decodificável, user.id' do
      token = login(email: 'ana@fabrica.com', password: 'senha123')

      expect(response).to have_http_status(:ok)
      expect(decode(token)['sub']).to eq(ana.id)
      expect(json.dig('data', 'user', 'id')).to eq(ana.id)
    end

    it 'recusa senha incorreta: 401 genérico, sem token' do
      post '/auth/v1/session', params: { email: 'ana@fabrica.com', password: 'senha124' }

      expect(response).to have_http_status(:unauthorized)
      expect(json['error']).to eq('E-mail ou senha inválidos.')
      expect(response.headers['Authorization']).to be_nil
    end

    it 'e-mail inexistente responde exatamente igual a senha errada' do
      post '/auth/v1/session', params: { email: 'ninguem@fabrica.com', password: 'qualquer' }
      corpo_inexistente = response.body
      status_inexistente = response.status

      post '/auth/v1/session', params: { email: 'ana@fabrica.com', password: 'errada' }

      expect(status_inexistente).to eq(response.status)
      expect(corpo_inexistente).to eq(response.body)
    end

    it 'conta só-Google (sem senha) não entra por senha: 401' do
      create(:user, :google_only, email: 'google@fabrica.com')

      post '/auth/v1/session', params: { email: 'google@fabrica.com', password: 'qualquer6' }

      expect(response).to have_http_status(:unauthorized)
      expect(response.headers['Authorization']).to be_nil
    end
  end

  # ---- TTL ligado ao "manter conectado" ------------------------------------
  describe 'TTL do token (D4.2)' do
    it 'remember_me=true → exp entre 29 e 30 dias' do
      token = login(email: 'ana@fabrica.com', password: 'senha123', remember_me: true)
      exp = decode(token)['exp']

      expect(exp).to be > 29.days.from_now.to_i
      expect(exp).to be <= 30.days.from_now.to_i + 5
    end

    it 'remember_me=false → exp entre 11 e 12 horas' do
      token = login(email: 'ana@fabrica.com', password: 'senha123', remember_me: false)
      exp = decode(token)['exp']

      expect(exp).to be > 11.hours.from_now.to_i
      expect(exp).to be <= 12.hours.from_now.to_i + 5
    end

    it 'token expirado é rejeitado em GET /auth/v1/me: 401' do
      get '/auth/v1/me', headers: { 'Authorization' => "Bearer #{expired_bearer_for(ana)}" }

      expect(response).to have_http_status(:unauthorized)
    end
  end

  # ---- Payload: identifica, não autoriza -----------------------------------
  describe 'payload do token' do
    it 'tem exatamente sub, jti, exp, iat, iat_origin — sem workspace_id/role' do
      token = login(email: 'ana@fabrica.com', password: 'senha123')

      expect(decode(token).keys).to contain_exactly('sub', 'jti', 'exp', 'iat', 'iat_origin')
    end
  end

  # ---- Logout revoga por denylist ------------------------------------------
  describe 'DELETE /auth/v1/session (logout)' do
    it 'invalida o token apresentado: 204, jti no denylist, me → 401' do
      token = login(email: 'ana@fabrica.com', password: 'senha123')
      jti = decode(token)['jti']

      delete '/auth/v1/session', headers: { 'Authorization' => "Bearer #{token}" }
      expect(response).to have_http_status(:no_content)
      expect(JwtDenylist.exists?(jti: jti)).to be(true)

      get '/auth/v1/me', headers: { 'Authorization' => "Bearer #{token}" }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'logout num dispositivo não derruba o outro' do
      token_a = login(email: 'ana@fabrica.com', password: 'senha123')
      token_b = login(email: 'ana@fabrica.com', password: 'senha123')

      delete '/auth/v1/session', headers: { 'Authorization' => "Bearer #{token_a}" }

      get '/auth/v1/me', headers: { 'Authorization' => "Bearer #{token_a}" }
      expect(response).to have_http_status(:unauthorized)
      get '/auth/v1/me', headers: { 'Authorization' => "Bearer #{token_b}" }
      expect(response).to have_http_status(:ok)
    end

    it 'logout sem token: 401 e nenhuma linha no denylist' do
      expect do
        delete '/auth/v1/session'
      end.not_to change(JwtDenylist, :count)

      expect(response).to have_http_status(:unauthorized)
    end

    it 'índice único impede jti duplicado no denylist' do
      jti = SecureRandom.uuid
      JwtDenylist.create!(jti: jti, exp: 1.hour.from_now)

      expect { JwtDenylist.create!(jti: jti, exp: 1.hour.from_now) }
        .to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  # ---- Renovação com rotação e teto ----------------------------------------
  describe 'POST /auth/v1/session/renew' do
    it 'rotaciona o jti: 200, novo jti, antigo no denylist, antigo → 401' do
      token_a = login(email: 'ana@fabrica.com', password: 'senha123')
      jti_a = decode(token_a)['jti']

      post '/auth/v1/session/renew', headers: { 'Authorization' => "Bearer #{token_a}" }
      expect(response).to have_http_status(:ok)
      token_b = json.dig('data', 'access_token')

      expect(decode(token_b)['jti']).not_to eq(jti_a)
      expect(JwtDenylist.exists?(jti: jti_a)).to be(true)

      get '/auth/v1/me', headers: { 'Authorization' => "Bearer #{token_a}" }
      expect(response).to have_http_status(:unauthorized)
      get '/auth/v1/me', headers: { 'Authorization' => "Bearer #{token_b}" }
      expect(response).to have_http_status(:ok)
    end

    it 'renew com token já revogado: 401' do
      token = login(email: 'ana@fabrica.com', password: 'senha123')
      delete '/auth/v1/session', headers: { 'Authorization' => "Bearer #{token}" }

      post '/auth/v1/session/renew', headers: { 'Authorization' => "Bearer #{token}" }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'recusa depois do teto absoluto iat_origin + 2×TTL' do
      now = Time.now.to_i
      # Token de sessão curta (TTL 12h) cujo iat_origin tem 25h: já passou de 2×12h.
      forged = JWT.encode(
        { 'sub' => ana.id.to_s, 'jti' => SecureRandom.uuid,
          'iat' => now - 3600, 'exp' => now + (11 * 3600), 'iat_origin' => now - (25 * 3600) },
        ::Auth::TokenService.secret, 'HS256'
      )

      post '/auth/v1/session/renew', headers: { 'Authorization' => "Bearer #{forged}" }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'preserva iat_origin através das renovações' do
      token_a = login(email: 'ana@fabrica.com', password: 'senha123')
      origin = decode(token_a)['iat_origin']

      post '/auth/v1/session/renew', headers: { 'Authorization' => "Bearer #{token_a}" }
      token_b = json.dig('data', 'access_token')
      post '/auth/v1/session/renew', headers: { 'Authorization' => "Bearer #{token_b}" }
      token_c = json.dig('data', 'access_token')

      expect(decode(token_c)['iat_origin']).to eq(origin)
    end
  end

  # ---- Superfície negativa (4.5) -------------------------------------------
  describe 'superfície protegida sem token' do
    it 'session/renew sem token → 401' do
      post '/auth/v1/session/renew'
      expect(response).to have_http_status(:unauthorized)
    end

    it 'me sem token → 401' do
      get '/auth/v1/me'
      expect(response).to have_http_status(:unauthorized)
    end

    it 'me com X-Skip-Auth: 1 e sem token → 401 (regressão de seal-template-baseline)' do
      get '/auth/v1/me', headers: { 'X-Skip-Auth' => '1' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'me com token de outro usuário devolve os dados desse usuário, não de um terceiro' do
      bruno = create(:user, :with_password, name: 'Bruno', email: 'bruno@fabrica.com')
      token_b = sign_in_as(bruno)

      get '/auth/v1/me', headers: { 'Authorization' => "Bearer #{token_b}" }
      expect(json.dig('data', 'user', 'id')).to eq(bruno.id)
      expect(json.dig('data', 'user', 'id')).not_to eq(ana.id)
    end
  end
end
