# frozen_string_literal: true

class OauthRedirectsController < ActionController::Base
  def google_oauth2
    code = params[:code]
    state = params[:state]
    frontend_callback = ENV['FRONTEND_CALLBACK_URL'] || ENV['OAUTH_REDIRECT_URI'] || 'http://localhost:5173/auth/callback'
    uri = URI.parse(frontend_callback)
    query = URI.encode_www_form({ provider: 'google', code: code.to_s, state: state.to_s })
    uri.query = [uri.query, query].compact.join('&')
    redirect_to uri.to_s
  end

  def facebook
    code = params[:code]
    state = params[:state]
    frontend_callback = ENV['FRONTEND_CALLBACK_URL'] || ENV['OAUTH_REDIRECT_URI'] || 'http://localhost:5173/auth/callback'
    uri = URI.parse(frontend_callback)
    query = URI.encode_www_form({ provider: 'facebook', code: code.to_s, state: state.to_s })
    uri.query = [uri.query, query].compact.join('&')
    redirect_to uri.to_s
  end
end
