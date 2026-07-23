# frozen_string_literal: true

module Observability
  # Redação de dado sensível (delivery-and-observability 4.1). Usado pelo
  # `before_send` do Sentry: um 500 com `{"password":"segredo123"}` no corpo NÃO
  # pode viajar para o rastreio de exceção. Recursivo (hash/array aninhados), por
  # correspondência de SUBSTRING no nome da chave — pega `invitation_token`,
  # `refresh_token`, `authorization`, etc. sem enumerar cada variação.
  module Scrubber
    SENSITIVE = %w[password secret token jwt authorization crypt salt otp ssn credential].freeze
    REDACTED = '[FILTERED]'

    module_function

    def sensitive_key?(key)
      k = key.to_s.downcase
      SENSITIVE.any? { |s| k.include?(s) }
    end

    def scrub(value)
      case value
      when Hash
        value.each_with_object({}) do |(k, v), acc|
          acc[k] = sensitive_key?(k) ? REDACTED : scrub(v)
        end
      when Array
        value.map { |v| scrub(v) }
      else
        value
      end
    end

    # Aplica sobre as partes de um evento Sentry que carregam dado do usuário.
    def scrub_event(event_hash)
      %w[request extra contexts].each do |section|
        event_hash[section] = scrub(event_hash[section]) if event_hash[section]
      end
      event_hash
    end
  end
end
