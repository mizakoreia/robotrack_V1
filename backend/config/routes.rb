# frozen_string_literal: true

Robotrack::Application.routes.draw do
  # Rotas Rails mínimas; todo roteamento da API é feito via Grape

  # Sondas de orquestrador (delivery-and-observability 2.3). ANTES do mount do
  # Grape em '/', senão seriam engolidas. Públicas, sem auth.
  get '/health/live', to: 'health#live'
  get '/health/ready', to: 'health#ready'

  # Monta Grape API
  mount Api::Root => '/'

  # Stoplight Elements para visualizar Swagger
  get '/docs', to: 'docs#elements'

  # Action Cable endpoint
  mount ActionCable.server => '/cable'

  # Google OAuth por redirect Devise OmniAuth (identity-and-auth). O request phase
  # é `POST /users/auth/google_oauth2` (omniauth-rails_csrf_protection) e o
  # callback `/users/auth/google_oauth2/callback` cai em Users::OmniauthCallbacks.
  devise_for :users, controllers: { omniauth_callbacks: 'users/omniauth_callbacks' }
end
