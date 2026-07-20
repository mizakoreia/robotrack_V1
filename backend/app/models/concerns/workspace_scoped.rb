# frozen_string_literal: true

# tenant-isolation / design D-1 (tarefa 3.3).
#
# Reforço ERGONÔMICO da tenancy no model — NÃO a garantia. A garantia é a RLS no
# banco (a spec de isolamento prova que `unscoped` continua isolado mesmo com
# este concern desligado). Duas conveniências:
#
# 1. `default_scope` filtra por `workspace_id` do contexto corrente, para que o
#    código de aplicação não precise repetir `where(workspace_id:)`.
# 2. Auto-atribui `workspace_id` na criação a partir do contexto — sem isso, todo
#    `create` teria de setar a coluna à mão, e esquecê-la violaria o NOT NULL e o
#    WITH CHECK da RLS.
module WorkspaceScoped
  extend ActiveSupport::Concern

  included do
    # `optional: true` de propósito: a presença de `workspace_id` é garantida
    # pelo NOT NULL, pela FK e pela RLS no banco. A validação de presença padrão
    # do belongs_to carregaria o Workspace por `find` — que é filtrado pela RLS —
    # e num contexto ausente/alheio levantaria "Workspace must exist" ANTES de o
    # INSERT chegar ao WITH CHECK, mascarando a violação de política como erro de
    # validação. Deixar opcional faz o fail-closed acontecer onde deve: no banco.
    belongs_to :workspace, optional: true

    default_scope do
      wsid = Tenant.current_workspace_id
      wsid ? where(workspace_id: wsid) : all
    end

    before_validation :assign_current_workspace, on: :create
  end

  private

  def assign_current_workspace
    self.workspace_id ||= Tenant.current_workspace_id
  end
end
