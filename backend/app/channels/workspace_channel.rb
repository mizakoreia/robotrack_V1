# frozen_string_literal: true

# realtime-collaboration 2.1–2.2 / D6.1, D6.7 — o ÚNICO canal de tempo real: um
# stream por workspace (`ws:<id>:v1`), por onde passam todos os eventos de domínio
# daquele workspace. Um canal por recurso faria a autorização ser decidida por
# objeto, multiplicando a superfície de erro; um canal por workspace decide a
# autorização UMA vez, no lugar mais barato de acertar — a membership no banco.
#
# A garantia é DUPLA (D6.1): (1) no `subscribed`, `resolve_workspace_or_reject`
# consulta a membership no banco e rejeita quem não pertence — não-membro e
# workspace inexistente dão a MESMA rejeição, indistinguível; (2) na ENTREGA de
# cada envelope, a membership é reverificada, porque autorização em T0 não é
# autorização em T+1h — se sumiu, para de entregar e encerra (a autorização não
# pode depender de o cliente cooperar). O envelope é ponteiro (D6.2): nenhum dado
# de conteúdo trafega aqui, e o `workspace_id` do envelope vem da própria linha
# sob RLS, então byte de workspace alheio não entra num stream errado.
class WorkspaceChannel < ApplicationCable::Channel
  # Nome do stream do workspace. Fonte única: o `PublisherService` (G3) emite
  # exatamente aqui.
  def self.stream_name(workspace_id)
    "ws:#{workspace_id}:v1"
  end

  def subscribed
    resolution = resolve_workspace_or_reject(params[:workspace_id])
    return unless resolution

    ws_id = resolution.workspace_id
    stream_from(self.class.stream_name(ws_id), coder: ActiveSupport::JSON) do |message|
      case delivery_decision(ws_id, message)
      when :transmit
        transmit(message)
      when :self_revoke
        # revogação viva (8.2/D6.7): deixa o usuário SABER que foi removido (o
        # ponteiro do próprio user_id, sem vazamento) e ENCERRA o stream — não
        # depende de o cliente cooperar; nenhum envelope posterior de W1 chega.
        transmit(message)
        reject_and_stop
      else
        reject_and_stop
      end
    end
  end

  private

  # Decisão de entrega por envelope (extraída para ser testável direto). Autorizado
  # → entrega; senão, se for a revogação DESTE usuário → entrega-e-encerra; senão
  # → descarta-e-encerra (fail-closed).
  def delivery_decision(workspace_id, message)
    return :transmit if still_authorized?(workspace_id)
    return :self_revoke if self_revocation?(message)

    :stop
  end

  def self_revocation?(message)
    message.is_a?(Hash) &&
      message['type'] == 'membership.revoked' &&
      message.dig('entity', 'user_id') == current_user&.id
  end

  # Reverificação na entrega (D6.1/D6.7). Reusa a MESMA regra do `subscribed`
  # (dono via `owner_user_id` OU membership ativa), consultada no banco.
  def still_authorized?(workspace_id)
    ActiveRecord::Base.transaction do
      Workspaces::ResolveCurrentService.new(user: current_user, workspace_id: workspace_id).call.ok
    end
  rescue StandardError
    # Falha ao reverificar é fail-closed: na dúvida, não entrega.
    false
  end

  # Encerra a entrega deste workspace. O gatilho por revogação de membership
  # (`after_commit` → broadcast de saída) e o teste dos 5 cenários são do G8; aqui
  # fica o mecanismo do lado do canal.
  def reject_and_stop
    stop_all_streams
  end
end
