# frozen_string_literal: true

# workspace-settings 1.3 (§4.1, D3) — a policy do painel de Equipe (e da tela em
# geral). Listar pessoas é leitura de qualquer membro (`read_workspace`, inclusive
# `view`); CRIAR e ARQUIVAR pessoa é `manage_catalog` (owner/edit — `view` recebe
# 403). Sem `update?`/`destroy?` de recurso arbitrário: arquivar é a única mutação,
# via `archive?`.
class WorkspaceSettingsPolicy < BasePolicy
  permits index?: :read_workspace,
          create?: :manage_catalog,
          archive?: :manage_catalog
end
