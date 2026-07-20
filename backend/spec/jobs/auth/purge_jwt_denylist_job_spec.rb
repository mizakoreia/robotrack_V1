# frozen_string_literal: true

require 'rails_helper'

# identity-and-auth 2.5/2.6 — a purga apaga o que já expirou e SÓ isso.
RSpec.describe Auth::PurgeJwtDenylistJob, type: :request do
  def json = JSON.parse(response.body)

  it 'apaga as linhas expiradas e preserva as vigentes' do
    3.times { JwtDenylist.create!(jti: SecureRandom.uuid, exp: 1.day.ago) }
    2.times { JwtDenylist.create!(jti: SecureRandom.uuid, exp: 1.day.from_now) }

    described_class.perform_now

    expect(JwtDenylist.count).to eq(2)
    expect(JwtDenylist.where('exp < ?', Time.current)).to be_empty
  end

  it 'não ressuscita um token revogado ainda vigente' do
    create(:user, :with_password, email: 'ana@fabrica.com', password: 'senha123')
    post '/auth/v1/session', params: { email: 'ana@fabrica.com', password: 'senha123' }
    token = json.dig('data', 'access_token')

    delete '/auth/v1/session', headers: { 'Authorization' => "Bearer #{token}" }
    described_class.perform_now # o token revogado ainda não expirou (12h)

    get '/auth/v1/me', headers: { 'Authorization' => "Bearer #{token}" }
    expect(response).to have_http_status(:unauthorized)
  end
end
