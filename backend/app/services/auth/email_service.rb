# frozen_string_literal: true

module Auth
  class EmailService
    include ActiveModel::Model
    include ApiResponseHandler

    attr_accessor :user, :code

    validates :user, presence: true
    validates :code, presence: true

    def initialize(attributes = {})
      super
    end

    def send_magic_login_code
      return validation_error_response('Dados inválidos', details: errors.full_messages) unless valid?

      AuthMailer.with(user_id: user.id, code: code).magic_login_code.deliver_later
      success_response({
                         message: 'Email enviado com sucesso',
                         email: user.email,
                         subject: "🔐 Seu código de acesso — #{ENV.fetch('APP_NAME', 'robotrack')}"
                       })
    rescue StandardError => e
      Rails.logger.error "[EmailService] Erro ao enviar email: #{e.message}"
      internal_error_response("Erro ao enviar email: #{e.message}")
    end

    def send_welcome_email
      return validation_error_response('Dados inválidos', details: errors.full_messages) unless valid?

      subject = 'Bem-vindo ao sistema!'
      body = build_welcome_email_body

      Rails.logger.info "[EmailService] Enviando email de boas-vindas para #{user.email}"
      Rails.logger.info "[EmailService] Assunto: #{subject}"
      Rails.logger.info "[EmailService] Corpo: #{body}"

      success_response({
                         message: 'Email de boas-vindas enviado com sucesso',
                         email: user.email,
                         subject: subject
                       })
    rescue StandardError => e
      Rails.logger.error "[EmailService] Erro ao enviar email de boas-vindas: #{e.message}"
      internal_error_response("Erro ao enviar email de boas-vindas: #{e.message}")
    end

    private

    def build_magic_login_email_body
      <<~HTML
        <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
          <div style="background: #f8f9fa; padding: 20px; border-radius: 8px;">
            <h2 style="color: #333; margin-bottom: 20px;">🔐 Código de Acesso</h2>
        #{'    '}
            <p style="font-size: 16px; color: #555; margin-bottom: 20px;">
              Olá <strong>#{user.name}</strong>,
            </p>
        #{'    '}
            <p style="font-size: 16px; color: #555; margin-bottom: 20px;">
              Use o código abaixo para acessar sua conta:
            </p>
        #{'    '}
            <div style="background: white; padding: 20px; border-radius: 8px; text-align: center; margin-bottom: 20px;">
              <h1 style="color: #007bff; font-size: 32px; margin: 0; letter-spacing: 4px;">
                #{code}
              </h1>
            </div>
        #{'    '}
            <p style="font-size: 14px; color: #888; margin-bottom: 20px;">
              ⏰ Este código expira em <strong>5 minutos</strong>
            </p>
        #{'    '}
            <div style="background: #fff3cd; border: 1px solid #ffeaa7; padding: 15px; border-radius: 5px; margin-bottom: 20px;">
              <p style="font-size: 14px; color: #856404; margin: 0;">
                <strong>⚠️ Importante:</strong> Não compartilhe este código com ninguém.
              </p>
            </div>
        #{'    '}
            <p style="font-size: 14px; color: #888;">
              Se você não solicitou este código, ignore este email.
            </p>
          </div>
        </div>
      HTML
    end

    def build_welcome_email_body
      <<~HTML
        <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
          <div style="background: #f8f9fa; padding: 20px; border-radius: 8px;">
            <h2 style="color: #333; margin-bottom: 20px;">🎉 Bem-vindo!</h2>
        #{'    '}
            <p style="font-size: 16px; color: #555; margin-bottom: 20px;">
              Olá <strong>#{user.name}</strong>,
            </p>
        #{'    '}
            <p style="font-size: 16px; color: #555; margin-bottom: 20px;">
              Seja bem-vindo ao nosso sistema! Estamos felizes em tê-lo conosco.
            </p>
        #{'    '}
            <div style="background: white; padding: 20px; border-radius: 8px; margin-bottom: 20px;">
              <h3 style="color: #007bff; margin-bottom: 10px;">Seus dados:</h3>
              <p style="font-size: 14px; color: #555; margin: 5px 0;">
                <strong>Email:</strong> #{user.email}
              </p>
              <p style="font-size: 14px; color: #555; margin: 5px 0;">
                <strong>Tipo de conta:</strong> #{user.user_type&.description}
              </p>
            </div>
        #{'    '}
            <p style="font-size: 14px; color: #888;">
              Se precisar de ajuda, não hesite em entrar em contato.
            </p>
          </div>
        </div>
      HTML
    end
  end
end
