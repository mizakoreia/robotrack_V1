# frozen_string_literal: true

# team-access-management §"Mudança de papel" e §"Remoção de membro" (tarefa 4.1).
#
# Ler a equipe é de qualquer membro — o painel mostra as listas a `edit` e `view`
# em modo leitura. MUTAR é só do dono. A ocultação dos botões na UI é
# conveniência; a fonte de autorização é isto (invariante 1), e o request spec
# negativo do grupo 4 chama a API direto, sem passar pela tela.
class MembershipPolicy < ApplicationPolicy
  def index?   = member?
  def update?  = owner?
  def destroy? = owner?
end
