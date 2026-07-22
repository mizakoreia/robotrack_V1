# frozen_string_literal: true

# audit-log 3.1 (§1.1, §2.8, Decisão 4/5/6) — uma entrada da trilha de auditoria.
# APPEND-ONLY: `readonly?` impede `save` de registro persistido (o banco tem REVOKE
# + trigger + RLS sem policy de mutação como rede; isto é só a mensagem amigável).
#
# `msg` e `ts_local` são texto RENDERIZADO e CONGELADO no INSERT (Decisão 4) — a
# leitura os usa verbatim, nunca re-renderiza (editar o locale não pode reescrever
# história). `by_name` é o snapshot imutável do autor (Decisão 6/D10), a única forma
# legítima de nome de pessoa no esquema junto do de `task_advances`.
#
# É também o NAMESPACE de `AuditLog::RecordService` e `AuditLog::ImmutabilityGuard`
# (a classe do model serve de namespace explícito para os service objects, Zeitwerk).
class AuditLog < ApplicationRecord
  include WorkspaceScoped

  self.primary_key = 'id' # a PK real é (ts, id) — id é o identificador de negócio

  belongs_to :author, class_name: 'Person', foreign_key: :by_person_id,
                      optional: true, inverse_of: false

  EVENT_TYPES = %w[task_completed workspace_reset].freeze

  # Versão publicada CORRENTE por evento (Decisão 5). Regra dura: uma vN publicada
  # NUNCA é editada — muda-se o texto criando vN+1 e incrementando aqui. O snapshot
  # congelado em spec/fixtures/audit/published_format_strings.yml guarda isso no CI.
  FORMAT_VERSIONS = { 'task_completed' => 1, 'workspace_reset' => 1 }.freeze

  validates :by_name, presence: true, length: { maximum: 200 }
  validates :msg, presence: true
  validates :event_type, inclusion: { in: EVENT_TYPES }

  def readonly?
    persisted?
  end
end
