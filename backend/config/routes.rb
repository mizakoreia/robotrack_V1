# frozen_string_literal: true

Robotrack::Application.routes.draw do
  # Rotas Rails mínimas; todo roteamento da API é feito via Grape

  # Monta Grape API
  mount Api::Root => '/'

  # Stoplight Elements para visualizar Swagger
  get '/docs', to: 'docs#elements'

  get '/auth/google_oauth2/callback', to: 'oauth_redirects#google_oauth2'
  get '/auth/facebook/callback', to: 'oauth_redirects#facebook'

  # Action Cable endpoint
  mount ActionCable.server => '/cable'

  devise_for :users, controllers: { omniauth_callbacks: 'users/omniauth_callbacks' }
end
