# frozen_string_literal: true

# §4.1 linhas 1 e 8: renomear/tema é `manage_catalog` (edit pode — análogo da
# rule legada L18-19, design "Perguntas em aberto" 2); destruir/reset é só do
# dono. Não existe action de transferência de propriedade (inv. 5, D3.8) — o
# dono é imutável por trigger e REVOKE de coluna.
class WorkspacePolicy < BasePolicy
  permits index?: :read_workspace,
          show?: :read_workspace,
          update?: :manage_catalog,
          destroy?: :destroy_workspace,
          factory_reset?: :destroy_workspace
end
