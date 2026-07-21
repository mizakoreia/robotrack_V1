# frozen_string_literal: true

# robot-tasks §1.1 (D-RT-3, D-RT-5, D-RT-7) — a Tarefa, unidade atômica do robô.
#
# `progress`/`status` são colunas com constraint no banco (CHECK 0–100 + enum
# `task_status`), mas READ-ONLY por esta capacidade: nenhum service de
# `robot-tasks` os muta — a máquina de estados §2.2 é de `progress-advances`. Os
# quatro literais de status são pt-BR, os MESMOS da spec, sem tradução na
# fronteira.
#
# `lock_version` liga o optimistic locking do ActiveRecord (D-RT-7): dois PATCH
# com a mesma versão → um 200 e um `StaleObjectError` (409), nunca dois 200.
#
# Ausência de responsável é conjunto VAZIO (`assignees == []`), nunca uma pessoa
# "Não Atribuído" (D10/D11) — ver `task_assignees`.
class Task < ApplicationRecord
  include WorkspaceScoped

  STATUSES = ['Pendente', 'Em Andamento', 'Concluído', 'N/A'].freeze

  belongs_to :robot

  validates :cat, :desc, presence: true
  validates :weight, numericality: { greater_than: 0 }
  validates :progress, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validates :status, inclusion: { in: STATUSES }

  before_validation :strip_text

  private

  def strip_text
    self.cat = cat.to_s.strip if cat
    self.desc = desc.to_s.strip if desc
  end
end
