import { create } from 'zustand'
import { persist } from 'zustand/middleware'

// workspace-core §"Índice do usuário" / D9 (tarefa 6.3).
//
// O workspace CORRENTE é estado de cliente. O PAPEL, não: ele vem da resposta do
// servidor e é apenas RÓTULO DE UI — nunca é lido daqui para decidir acesso.
// Adulterar este store (ou o localStorage) não concede nada: toda request de
// domínio leva só o `X-Workspace-Id` (um id), e o servidor resolve o papel de
// novo a partir de owner_user_id/memberships (§4.1 inv. 2).
export interface WorkspaceSummary {
  id: string
  name: string
  role: string // rótulo, não autoridade
}

interface WorkspaceState {
  currentWorkspaceId: string | null
  // Rótulo do papel no workspace corrente, vindo do servidor. Apenas exibição.
  currentRoleLabel: string | null
  workspaces: WorkspaceSummary[]

  setWorkspaces: (workspaces: WorkspaceSummary[]) => void
  selectWorkspace: (id: string) => void
  clear: () => void
}

export const useWorkspaceStore = create<WorkspaceState>()(
  persist(
    (set, get) => ({
      currentWorkspaceId: null,
      currentRoleLabel: null,
      workspaces: [],

      setWorkspaces: (workspaces) => {
        set({ workspaces })
        // Reidrata o rótulo do papel corrente a partir da lista do servidor.
        const current = get().currentWorkspaceId
        const match = current ? workspaces.find((w) => w.id === current) : undefined
        set({ currentRoleLabel: match ? match.role : get().currentRoleLabel })
      },

      selectWorkspace: (id) => {
        const match = get().workspaces.find((w) => w.id === id)
        set({ currentWorkspaceId: id, currentRoleLabel: match ? match.role : null })
      },

      clear: () => set({ currentWorkspaceId: null, currentRoleLabel: null, workspaces: [] }),
    }),
    {
      name: 'workspace',
      // Persiste SÓ o id. O papel é sempre re-derivado do servidor — nunca
      // confiado a partir do storage do cliente (D9).
      partialize: (state) => ({ currentWorkspaceId: state.currentWorkspaceId }),
    }
  )
)
