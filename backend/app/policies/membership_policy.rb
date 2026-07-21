# frozen_string_literal: true

# §4.1 linhas 1 e 7: qualquer membro LÊ a equipe (o painel mostra as listas a
# edit e view em modo leitura); gerenciar membros é só do dono. A ocultação de
# botões na UI é conveniência; a fonte de autorização é isto (inv. 1).
# Singleton D3.1 — absorve o piso de instância de workspace-invitations.
class MembershipPolicy < BasePolicy
  permits index?: :read_workspace,
          show?: :read_workspace,
          create?: :manage_membership,
          update?: :manage_membership,
          destroy?: :manage_membership
end
