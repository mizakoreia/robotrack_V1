# frozen_string_literal: true

# task-catalog §1.1 / §3.9 (D-TC-2) — o template é a tarefa-base do workspace.
#
# `app_filters` é normalizado na ESCRITA: vazio, `Misto / Geral` ou `Todas`
# significam "vale para todo robô" e colapsam para `[]`. Assim a predicate de
# §2.5 nunca precisa reinterpretar sentinela, e um `TaskTemplate.create!` do
# console persiste o mesmo que a API — o legado guardava as três formas e a
# tela tinha de adivinhar.
class TaskTemplate < ApplicationRecord
  include WorkspaceScoped

  # `desc` colide com `Object#desc`? Não — mas `desc` é palavra reservada do
  # SQL; o adapter faz o quoting. O acessor do Rails funciona normalmente.
  TODOS_OS_ROBOS = ['Misto / Geral', 'Todas'].freeze

  # task-catalog 3.5 (§1.3 nota, D-TC-1) — a ordem das 9 categorias vem da
  # ordenação lexicográfica do prefixo (`A. `, `B. `…) DENTRO de `cat`, com
  # collation BINÁRIA explícita (`COLLATE "C"`). Sem ela, um locale como
  # `pt_BR.UTF-8` ignora pontuação e a ordem das categorias muda entre ambientes
  # — bug que só aparece em produção. `"desc"` também com `COLLATE "C"` para a
  # ordem dentro da categoria ser igualmente determinística.
  scope :ordered, -> { order(Arel.sql('cat COLLATE "C", "desc" COLLATE "C"')) }

  before_validation :normalize_fields

  validates :cat, :desc, presence: true
  validates :weight, numericality: { greater_than: 0 }
  validate :app_filters_no_dominio

  private

  def normalize_fields
    self.cat = cat.to_s.strip
    self.desc = desc.to_s.strip
    self.app_filters = normalized_filters
  end

  def normalized_filters
    filtros = Array(app_filters).map { |f| f.to_s.strip }.reject(&:empty?)
    return [] if filtros.empty? || filtros.any? { |f| TODOS_OS_ROBOS.include?(f) }

    filtros.uniq
  end

  def app_filters_no_dominio
    invalidos = app_filters - Robot::APPLICATIONS
    return if invalidos.empty?

    errors.add(:app_filters, "valores fora da §1.2: #{invalidos.join(', ')}")
  end
end
