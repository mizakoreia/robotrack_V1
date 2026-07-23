# frozen_string_literal: true

# realtime-collaboration 3.4 / D6.4 — atributos por request (ActiveSupport
# CurrentAttributes, reset automático pelo executor a cada request).
#
# - `origin_id`: o UUID da ABA que originou a mutação (header `X-RoboTrack-Origin`).
#   Copiado para o envelope; o cliente descarta o próprio eco por ele, matando o
#   flicker auto-infligido do otimista (quem registrou 40→60 não refetcha por cima
#   de si mesmo).
# - `user_id` / `actor_person_id`: quem agiu, para reabrir o contexto de tenant no
#   `after_commit` (o SET LOCAL da request já morreu no COMMIT) e para o
#   `actor_person_id` do envelope.
# - `suppress_realtime`: seam de supressão por linha (3.5). Hoje os caminhos em
#   massa usam `insert_all`/`update_all` (sem callback → sem evento por linha), mas
#   um futuro caminho que use `create!` em laço pode se envolver em
#   `Realtime.suppress` e emitir só o agregado terminal.
class Current < ActiveSupport::CurrentAttributes
  attribute :origin_id, :user_id, :actor_person_id, :suppress_realtime
end
