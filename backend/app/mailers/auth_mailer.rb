# frozen_string_literal: true

class AuthMailer < ApplicationMailer
  def magic_login_code
    @code = params[:code]
    user_id = params[:user_id]
    @user = User.find_by(id: user_id)
    return if @user.nil?

    mail(to: @user.email, subject: '🔐 Seu código de acesso')
  end
end
