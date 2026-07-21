# frozen_string_literal: true

# commissioning-hierarchy 2.3 (§2.9, D-H3).
#
# Ordem manual: item novo entra em `position = MAX(position) + 1` (ou 0) do seu
# ESCOPO, calculado dentro da transação do INSERT, sob lock do escopo — duas
# criações simultâneas na mesma célula não produzem dois robôs na mesma posição.
#
# O lock é um ADVISORY LOCK transacional sobre o uuid do escopo, não um
# `SELECT ... FOR UPDATE` na linha pai. Deliberado: para `projects` o "pai" é a
# linha do workspace, e o `robotrack_app` NÃO tem privilégio de UPDATE de tabela
# em `workspaces` (roles.sql revogou; só colunas name/updated_at) — `FOR UPDATE`
# falharia com permission denied. O advisory lock dá a mesma serialização nos
# três níveis com um mecanismo só, sem exigir privilégio nenhum, e morre com a
# transação. `Hierarchy::ReorderService` (G4) usa o MESMO lock — criação e
# reordenação do mesmo escopo nunca se cruzam.
module PositionScoped
  extend ActiveSupport::Concern

  # Namespace fixo do advisory lock desta feature (o outro int32 é o hash do
  # escopo). Qualquer outro uso de advisory lock no app deve escolher outro.
  LOCK_NAMESPACE = 730_001

  class_methods do
    attr_reader :position_scope_column

    def position_scoped_by(column)
      @position_scope_column = column
    end

    # Serializa criações/reordenações do escopo até o fim da transação corrente.
    def lock_position_scope!(scope_value)
      connection.execute(
        "SELECT pg_advisory_xact_lock(#{LOCK_NAMESPACE}, hashtext(#{connection.quote(scope_value.to_s)}))"
      )
    end
  end

  included do
    before_create :assign_next_position
  end

  private

  def assign_next_position
    return unless position.nil?

    scope_column = self.class.position_scope_column
    scope_value = public_send(scope_column)
    self.class.lock_position_scope!(scope_value)

    max = self.class.unscoped.where(scope_column => scope_value).maximum(:position)
    self.position = max ? max + 1 : 0
  end
end
