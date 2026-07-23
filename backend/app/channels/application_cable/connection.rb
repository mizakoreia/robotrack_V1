# frozen_string_literal: true

module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      self.current_user = find_verified_user
    end

    private

    # Ponto de estrangulamento do Cable: nenhum canal é instanciado sem passar
    # por aqui, então um canal futuro não pode esquecer de verificar identidade
    # (só pode esquecer de verificar autorização, que é problema da D3/D6).
    #
    # Autenticação por TICKET (realtime-collaboration 1.1 / D6.8), não mais por
    # `?token=`: o ticket é opaco, de uso único e 60s, consumido com GETDEL. Um
    # ticket ausente, expirado, já consumido ou desconhecido cai em `nil` e a
    # conexão é REJEITADA — nunca estabelecida com `current_user = nil` como no
    # template. O caminho `?token=` deixou de existir: um JWT de sessão na query
    # string do handshake não é aceito (a prova é o spec do grupo 1).
    def find_verified_user
      user = ::Realtime::CableTicketService.consume(request.params[:ticket])
      reject_unauthorized_connection if user.nil?
      user
    end
  end
end
