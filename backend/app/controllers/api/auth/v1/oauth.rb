# frozen_string_literal: true

require 'grape'
require 'faraday'
require 'json'
require 'uri'
require 'securerandom'

module Api
  module Auth
    module V1
      class Oauth < Grape::API
        namespace :oauth do
          resource :google_url do
            desc 'Inicia fluxo OAuth com Google' do
              summary 'Obter URL de autorização do Google'
              detail 'Gera a URL de autorização para iniciar o fluxo OAuth com Google.'
              success [code: 200, message: 'URL de autorização']
              failure [
                { code: 400, message: 'Dados inválidos' }
              ]
            end

            params do
              optional :redirect_uri, type: String, desc: 'URI de redirecionamento'
              optional :state, type: String, desc: 'Token de estado anti-CSRF'
            end

            get do
              redirect_uri = ENV['OAUTH_GOOGLE_REDIRECT_URI']
              client_id = Rails.application.credentials.dig(:oauth, :google, :client_id)
              state = params[:state].presence || SecureRandom.hex(16)
              query = URI.encode_www_form(
                client_id: client_id,
                redirect_uri: redirect_uri,
                response_type: 'code',
                scope: 'email profile',
                access_type: 'offline',
                include_granted_scopes: 'true',
                prompt: 'consent',
                state: state
              )
              url = "https://accounts.google.com/o/oauth2/v2/auth?#{query}"
              data = { url: url, provider: 'google', state: state }
              process_service_response({ status: 200, data: data })
            end
          end

          resource :facebook_url do
            desc 'Inicia fluxo OAuth com Facebook' do
              summary 'Obter URL de autorização do Facebook'
              detail 'Gera a URL de autorização para iniciar o fluxo OAuth com Facebook.'
              success [code: 200, message: 'URL de autorização']
              failure [
                { code: 400, message: 'Dados inválidos' }
              ]
            end

            params do
              optional :redirect_uri, type: String, desc: 'URI de redirecionamento'
              optional :state, type: String, desc: 'Token de estado anti-CSRF'
            end

            get do
              redirect_uri = ENV['OAUTH_FACEBOOK_REDIRECT_URI']
              client_id = Rails.application.credentials.dig(:oauth, :facebook, :app_id)
              state = params[:state].presence || SecureRandom.hex(16)
              query = URI.encode_www_form(
                client_id: client_id,
                redirect_uri: redirect_uri,
                response_type: 'code',
                scope: 'email,public_profile',
                state: state
              )
              url = "https://www.facebook.com/v19.0/dialog/oauth?#{query}"
              data = { url: url, provider: 'facebook', state: state }
              process_service_response({ status: 200, data: data })
            end
          end

          resource :callback do
            desc 'Processa callback OAuth e realiza login' do
              summary 'Callback OAuth'
              detail 'Processa o callback do provedor OAuth e realiza o login do usuário.'
              success [code: 200, message: 'Login realizado']
              failure [
                { code: 400, message: 'Dados inválidos' },
                { code: 401, message: 'Autenticação falhou' },
                { code: 500, message: 'Erro interno' }
              ]
            end

            params do
              requires :provider, type: String, values: %w[google facebook], desc: 'Provedor OAuth'
              requires :code, type: String, desc: 'Código de autorização'
              optional :state, type: String, desc: 'Estado CSRF'
            end

            post do
              provider = params[:provider]
              auth_code = params[:code]
              redirect_uri = case provider
                             when 'google'
                               ENV['OAUTH_GOOGLE_REDIRECT_URI'] || ENV['OAUTH_REDIRECT_URI'] || 'http://localhost:5173/auth/callback'
                             when 'facebook'
                               ENV['OAUTH_FACEBOOK_REDIRECT_URI'] || ENV['OAUTH_REDIRECT_URI'] || 'http://localhost:5173/auth/callback'
                             else
                               error!({ error: 'invalid_provider', message: 'Provedor inválido' }, 400)
                             end

              oauth_data = fetch_oauth_user(provider, auth_code, redirect_uri)

              result = Auth::OauthService.new(
                provider: provider,
                provider_uid: oauth_data[:uid],
                email: oauth_data[:email],
                name: oauth_data[:name],
                avatar_url: oauth_data[:avatar_url],
                ip_address: current_ip,
                user_agent: current_user_agent
              ).execute!

              process_service_response(result)
            end
          end
        end

        private

        def fetch_oauth_user(provider, code, redirect_uri)
          if provider == 'google'
            client_id = Rails.application.credentials.dig(:oauth, :google, :client_id)
            client_secret = Rails.application.credentials.dig(:oauth, :google, :client_secret)
            token_resp = Faraday.post('https://oauth2.googleapis.com/token', {
                                        client_id: client_id,
                                        client_secret: client_secret,
                                        code: code,
                                        redirect_uri: redirect_uri,
                                        grant_type: 'authorization_code'
                                      })
            error!({ error: 'oauth_error', message: 'Falha ao obter token do Google' }, 401) unless token_resp.success?
            token_body = JSON.parse(token_resp.body)
            access_token = token_body['access_token']
            user_resp = Faraday.get('https://www.googleapis.com/oauth2/v2/userinfo') do |req|
              req.headers['Authorization'] = "Bearer #{access_token}"
            end
            error!({ error: 'oauth_error', message: 'Falha ao obter perfil do Google' }, 401) unless user_resp.success?
            user = JSON.parse(user_resp.body)
            {
              uid: user['id'] || token_body['id_token'],
              email: user['email'],
              name: user['name'] || user['given_name'],
              avatar_url: user['picture']
            }
          elsif provider == 'facebook'
            app_id = Rails.application.credentials.dig(:oauth, :facebook, :app_id)
            app_secret = Rails.application.credentials.dig(:oauth, :facebook, :app_secret)
            token_resp = Faraday.get('https://graph.facebook.com/v19.0/oauth/access_token', {
                                       client_id: app_id,
                                       client_secret: app_secret,
                                       code: code,
                                       redirect_uri: redirect_uri
                                     })
            unless token_resp.success?
              error!({ error: 'oauth_error', message: 'Falha ao obter token do Facebook' },
                     401)
            end
            token_body = JSON.parse(token_resp.body)
            access_token = token_body['access_token']
            user_resp = Faraday.get('https://graph.facebook.com/me',
                                    { fields: 'id,name,email,picture', access_token: access_token })
            unless user_resp.success?
              error!({ error: 'oauth_error', message: 'Falha ao obter perfil do Facebook' },
                     401)
            end
            user = JSON.parse(user_resp.body)
            picture = user.dig('picture', 'data', 'url') if user['picture'].is_a?(Hash)
            {
              uid: user['id'],
              email: user['email'],
              name: user['name'],
              avatar_url: picture
            }
          else
            error!({ error: 'invalid_provider', message: 'Provedor inválido' }, 400)
          end
        end
      end
    end
  end
end
