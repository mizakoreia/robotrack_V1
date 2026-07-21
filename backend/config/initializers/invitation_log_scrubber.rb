# frozen_string_literal: true

# workspace-invitations 6.1 — o token de convite NUNCA em claro no log.
#
# O `filter_parameters` do Rails cobre `params[:token]`, mas o token de convite
# viaja no **PATH** (`POST /api/v1/invitations/rt_inv_ABC.../accept`), e path não
# passa por filtro de parâmetro: a linha "Started POST …" o gravaria inteiro. O
# mesmo vale para o INSERT do ActiveRecord, que loga o valor da coluna `token`.
#
# Um log de aplicação costuma ir para disco, para um agregador e para o terminal
# de quem está de plantão — três lugares onde uma credencial de uso único não
# deve estar. Este scrubber troca qualquer `rt_inv_<...>` pelo prefixo mais 12
# chars de SHA-256, o mesmo identificador que o bloqueio de rate limit registra:
# dá para correlacionar tentativas do mesmo token sem poder reconstruí-lo.
require 'delegate'

module InvitationLogScrubber
  TOKEN = /rt_inv_[A-Za-z0-9_-]+/

  # Delegator, não lambda: `ActiveSupport::TaggedLogging` chama `push_tags`,
  # `pop_tags` e `tagged` NO FORMATTER. Um lambda solto no lugar dele quebra o
  # logger inteiro na primeira request — foi exatamente o que aconteceu na
  # primeira tentativa desta implementação.
  class Formatter < SimpleDelegator
    def call(severity, time, progname, msg)
      __getobj__.call(severity, time, progname, msg.is_a?(String) ? InvitationLogScrubber.scrub(msg) : msg)
    end

    def invitation_scrubbed? = true
  end

  module_function

  def scrub(message)
    return message unless message.is_a?(String) && message.include?('rt_inv_')

    message.gsub(TOKEN) { |token| "rt_inv_[FILTERED:#{Digest::SHA256.hexdigest(token)[0, 12]}]" }
  end

  def install!(logger)
    return if logger.nil?

    if logger.respond_to?(:broadcasts)
      logger.broadcasts.each { |sink| install!(sink) }
      return
    end

    original = logger.formatter || ::ActiveSupport::Logger::SimpleFormatter.new
    return if original.respond_to?(:invitation_scrubbed?)

    logger.formatter = Formatter.new(original)
  end
end

Rails.application.config.after_initialize do
  InvitationLogScrubber.install!(Rails.logger)
end
