# frozen_string_literal: true

module Invitations
  # workspace-invitations 6.2 / D-INV-9 — expurgo diário.
  #
  # Apaga SÓ convites `used_at IS NULL` expirados há mais de 30 dias. Duas
  # decisões deliberadas dentro dessa frase:
  #
  # - **Os consumidos NUNCA são apagados.** `memberships.invitation_id` os
  #   referencia com `ON DELETE RESTRICT`, e essa referência é a prova auditável
  #   de por que aquela pessoa tem acesso. O job nem tenta: o predicado os exclui.
  # - **A janela de 30 dias ALÉM da expiração** existe para a mensagem: quem
  #   clica num link velho recebe `410 invitation_expired` ("peça um novo") em vez
  #   de `404 invitation_not_found` ("confira o link"), durante o período em que
  #   o link ainda circula por e-mail e mensagem.
  #
  # NÃO é `tenant: true`: é manutenção global, sem workspace corrente. Por isso a
  # remoção passa pela função `purge_expired_invitations()`, cujo predicado É o
  # critério do expurgo (ver migration AddInvitationPurgeFunction).
  #
  # DEPENDÊNCIA DE ENTREGA: o agendamento diário em produção é de
  # `delivery-and-observability` (ver config/sidekiq_cron.yml). Sem ele a tabela
  # cresce indefinidamente com convites que ninguém mais pode usar.
  class PurgeExpiredJob < ApplicationJob
    queue_as :default

    def perform
      removidos = ActiveRecord::Base.connection.select_value('SELECT purge_expired_invitations()').to_i
      Rails.logger.info({ event: 'invitations_purged', count: removidos }.to_json)
      removidos
    end
  end
end
