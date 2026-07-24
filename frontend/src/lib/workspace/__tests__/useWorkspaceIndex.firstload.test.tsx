import { describe, expect, it, vi, beforeEach } from 'vitest'
import { renderHook, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import type { ReactNode } from 'react'

// REGRESSÃO do BUG 13 — PRIMEIRA CARGA com localStorage VAZIO. D9 só persiste o
// `currentWorkspaceId`; num navegador novo ele nasce null. Sem auto-seleção, nada
// abre o tenant: o `X-Workspace-Id` não vai em request nenhuma (client.ts só o
// envia se houver id), a RLS não abre, e o DONO aparece "Somente leitura". Os
// testes de WorkspaceContext passavam papel explícito — o caminho real de primeiro
// uso não tinha cobertura, o mesmo padrão dos bugs 4/5/6/8/9/10/11.

const listMock = vi.fn()
vi.mock('@/lib/api/endpoints', () => ({
  workspacesApi: { list: () => listMock() },
}))

import { useWorkspaceIndex } from '../useWorkspaceIndex'
import { useWorkspaceStore } from '@/store/workspaceStore'

const OWN = { id: 'ws-own', name: 'Workspace de Mizael', role: 'owner' }
const OTHER = { id: 'ws-other', name: 'Linha 3', role: 'edit' }

function wrapper() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  return ({ children }: { children: ReactNode }) => (
    <QueryClientProvider client={qc}>{children}</QueryClientProvider>
  )
}

describe('useWorkspaceIndex — primeira carga (BUG 13)', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    useWorkspaceStore.setState({ currentWorkspaceId: null, currentRoleLabel: null, workspaces: [] })
  })

  it('sem corrente, auto-seleciona o PRÓPRIO (owner) e deriva o papel "owner"', async () => {
    listMock.mockResolvedValue([OTHER, OWN]) // owner não é o primeiro da lista
    renderHook(() => useWorkspaceIndex(), { wrapper: wrapper() })

    await waitFor(() => {
      expect(useWorkspaceStore.getState().currentWorkspaceId).toBe(OWN.id)
    })
    // O badge deixa de ser "Somente leitura": o papel corrente é o do servidor.
    expect(useWorkspaceStore.getState().currentRoleLabel).toBe('owner')
  })

  it('com corrente já selecionado, NÃO sobrescreve na primeira carga', async () => {
    useWorkspaceStore.setState({ currentWorkspaceId: OTHER.id })
    listMock.mockResolvedValue([OTHER, OWN])
    renderHook(() => useWorkspaceIndex(), { wrapper: wrapper() })

    await waitFor(() => {
      expect(useWorkspaceStore.getState().workspaces.length).toBe(2)
    })
    expect(useWorkspaceStore.getState().currentWorkspaceId).toBe(OTHER.id)
  })

  it('define um X-Workspace-Id: currentWorkspaceId deixa de ser null (o header passa a ir)', async () => {
    listMock.mockResolvedValue([OWN])
    renderHook(() => useWorkspaceIndex(), { wrapper: wrapper() })

    await waitFor(() => {
      // client.ts só envia X-Workspace-Id quando este valor existe; provar que ele
      // fica setado é provar que a próxima request leva contexto de tenant.
      expect(useWorkspaceStore.getState().currentWorkspaceId).not.toBeNull()
    })
  })
})
