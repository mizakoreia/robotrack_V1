# frozen_string_literal: true

# progress-advances 2.1 (§1.1, D-IMUT, D-CMT, D-LEG) — uma entrada da trilha de
# comissionamento. APPEND-ONLY: `readonly?` impede `save` de registro já
# persistido (o banco tem REVOKE + trigger como rede; isto é a mensagem amigável).
#
# As validações ESPELHAM as CHECKs do banco só para produzir 422 pt-BR antes de o
# Postgres reclamar — a GARANTIA é a constraint, não isto. `author_name_snapshot`
# é o único nome legítimo do esquema (snapshot histórico imutável, D10/D11).
class TaskAdvance < ApplicationRecord
  include WorkspaceScoped

  self.ignored_columns = [] # nada; `by` é atributo normal

  belongs_to :task
  belongs_to :author, class_name: 'Person', foreign_key: :by, optional: true, inverse_of: false

  validates :author_name_snapshot, presence: true, length: { maximum: 200 }
  validates :recorded_at, presence: true
  validates :from_progress, :to_progress,
            numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validates :comment, length: { maximum: 1000 }, allow_nil: true
  validate :comment_required_below_100
  validate :author_present_unless_legacy

  # Append-only: uma vez persistido, não há UPDATE possível pela aplicação.
  def readonly?
    persisted?
  end

  private

  def comment_required_below_100
    return if to_progress == 100 || legacy
    return if comment.present? && comment.strip.present?

    errors.add(:comment, :required_below_100)
  end

  def author_present_unless_legacy
    return if legacy || by.present?

    errors.add(:by, :required_unless_legacy)
  end
end
