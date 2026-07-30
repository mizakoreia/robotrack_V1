# frozen_string_literal: true

# send-feedback — enviar feedback é ação de QUALQUER membro (owner/edit/view):
# `submit_feedback`, mesma natureza self-service do `mark_notification_read`. LER a
# caixa de feedbacks é do DONO: `read_feedbacks` (owner-only) — a leitura é do
# dono do workspace, não de editores/visualizadores. Ambas consultam a matriz
# (fail-closed p/ papel nulo); não-membro cai em 404 pelo `BasePolicy`.
class FeedbackPolicy < BasePolicy
  permits index?: :read_feedbacks,
          create?: :submit_feedback
end
