# frozen_string_literal: true

module Realtime
  # realtime-collaboration 1.1 / D6.8 — ticket de vida curta que autentica a
  # conexão do ActionCable sem levar o JWT de sessão na query string do handshake.
  #
  # O `Upgrade:` de WebSocket no browser não permite header `Authorization`, então
  # alguma credencial tem de ir na URL — e a URL do handshake cai no `access.log`
  # do proxy, no log do Rails e no histórico de APM. Um JWT de sessão ali é
  # comprometimento da sessão inteira a partir de um log. O ticket é opaco, de USO
  # ÚNICO e validade de 60s: emitido em `POST /api/v1/cable_tickets` (Bearer
  # normal), guardado no Redis em `cable_ticket:<jti>` com TTL, e CONSUMIDO com
  # `GETDEL` (atômico) no `Connection#connect`. Vazado num log, é inútil na hora
  # em que alguém o lê.
  #
  # `issue` e `consume` rodam em PROCESSOS distintos (o Puma emite; o servidor do
  # Cable consome), então o armazenamento é compartilhado — Redis, nunca memória
  # de processo. Abrimos uma conexão curta por operação (caminho frio: uma vez por
  # conexão de Cable) em vez de compartilhar um cliente `redis-rb` 4.x, que não é
  # seguro entre as threads do servidor do Cable.
  class CableTicketService
    TTL_SECONDS = 60
    KEY_PREFIX = 'cable_ticket:'

    class << self
      # Emite um ticket opaco para `user` e devolve a string (o próprio `jti`).
      def issue(user)
        jti = SecureRandom.urlsafe_base64(24)
        with_redis { |r| r.set("#{KEY_PREFIX}#{jti}", user.id.to_s, ex: TTL_SECONDS) }
        jti
      end

      # Consome o ticket (GETDEL) e devolve o `User` dono, ou `nil` quando o
      # ticket está ausente, expirado, já consumido ou desconhecido — o
      # `Connection` trata todos esses casos como rejeição (fail-closed). Redis
      # fora do ar também cai em `nil`: uma conexão a menos, nunca uma exceção que
      # vaze para o handshake.
      def consume(ticket)
        return nil if ticket.blank?

        user_id = with_redis { |r| r.getdel("#{KEY_PREFIX}#{ticket}") }
        return nil if user_id.blank?

        User.find_by(id: user_id)
      rescue StandardError => e
        Rails.logger.warn({ event: 'cable_ticket_consume_error', error: e.class.name }.to_json)
        nil
      end

      # Conexão curta com o Redis dos tickets. Público de propósito: o spec do
      # grupo 1 escreve uma chave com TTL mínimo para provar a rejeição por
      # expiração pela via real do Redis, sem esperar 60s.
      def with_redis
        client = ::Redis.new(url: redis_url)
        yield client
      ensure
        client&.close
      end

      private

      def redis_url
        ENV.fetch('CABLE_REDIS_URL', ENV.fetch('REDIS_URL', 'redis://localhost:6379/1'))
      end
    end
  end
end
