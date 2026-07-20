# frozen_string_literal: true

class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch('MAILER_FROM', 'no-reply@poelmk.com')
  layout 'mailer'
end
