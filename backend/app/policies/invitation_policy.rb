# frozen_string_literal: true

# workspace-invitations §"Criação de convite restrita ao dono" (tarefa 2.2 /
# invariante 7, `firestore.rules` L72-77).
#
# No legado a condição era `wsId == request.auth.uid` — o id do workspace ERA o
# uid do dono, então "workspace do próprio criador" e "sou o dono" colapsavam.
# Aqui essa identidade não existe, então a condição é explícita: só `owner` do
# workspace CORRENTE cria, lista e revoga convites. O papel chega já resolvido
# pelo servidor; `edit` e `view` recebem 403.
class InvitationPolicy < ApplicationPolicy
  def index?   = owner?
  def create?  = owner?
  def destroy? = owner?
end
