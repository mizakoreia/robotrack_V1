# frozen_string_literal: true

# Piso mínimo de policies (workspace-invitations, decisão de execução 1).
#
# `authorization-policies` (D3) é a change DONA do mecanismo geral e ainda não
# foi entregue. Duas saídas ruins seriam: (a) inventar aqui o mecanismo inteiro
# daquela change, que depois competiria com o dela; (b) deixar a autorização
# solta dentro dos endpoints, que é exatamente o que a invariante 1 proíbe.
#
# Este é o meio-termo: um objeto por recurso, decidindo a partir do papel
# RESOLVIDO NO SERVIDOR (`Workspaces::ResolveCurrentService`, exposto em
# `env['api.current_role']`) — nunca de algo que o cliente envie. Quando
# `authorization-policies` chegar, absorve estes objetos: a forma
# (`policy.create?`, `policy.destroy?`, …) já é a dela.
class ApplicationPolicy
  attr_reader :role, :user, :workspace_id

  def initialize(role:, user: nil, workspace_id: nil)
    @role = role&.to_sym
    @user = user
    @workspace_id = workspace_id
  end

  def owner? = role == :owner
  def edit?  = role == :edit
  def view?  = role == :view
  def member? = %i[owner edit view].include?(role)

  # Padrão fail-closed: um recurso que não sobrescreva nada nega tudo.
  def index?   = false
  def show?    = false
  def create?  = false
  def update?  = false
  def destroy? = false
end
