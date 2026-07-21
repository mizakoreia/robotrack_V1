import { describe, it, expect, vi, beforeEach } from 'vitest'

// workspace-invitations 5.3/5.5 — a rotina de revogação de acesso, e o fecho do
// fluxo completo do lado do cliente.
//
// As falhas a caçar: o aviso sumir sozinho (o usuário é levado para outra tela
// no mesmo instante — um toast de 4 segundos é a mesma coisa que não avisar);
// dados do workspace perdido continuarem no cache do React Query e reaparecerem
// na próxima tela; e o usuário terminar numa tela vazia em vez do próprio
// workspace.

const { toastMock } = vi.hoisted(() => ({
  toastMock: { warning: vi.fn(), error: vi.fn(), success: vi.fn(), info: vi.fn() },
}))

vi.mock('sonner', () => ({ toast: toastMock }))

import { handleAccessRevoked, registerRevocationNavigator, resetAccessRevokedState } from '../accessRevoked'
import { useWorkspaceStore } from '../../../store/workspaceStore'
import { queryClient } from '../../queryClient'

const WS_A = 'ws-a'
const WS_PROPRIO = 'ws-proprio'

describe('handleAccessRevoked', () => {
  let navegou: string[]

  beforeEach(() => {
    vi.clearAllMocks()
    resetAccessRevokedState()
    queryClient.clear()
    navegou = []
    registerRevocationNavigator((path) => navegou.push(path))
    useWorkspaceStore.setState({
      currentWorkspaceId: WS_A,
      currentRoleLabel: 'edit',
      workspaces: [
        { id: WS_A, name: 'Linha 3', role: 'edit' },
        { id: WS_PROPRIO, name: 'Workspace de Edu', role: 'owner' },
      ],
    })
  })

  it('avisa de forma PERSISTENTE, nomeando o workspace perdido', () => {
    handleAccessRevoked(WS_A)

    expect(toastMock.warning).toHaveBeenCalledTimes(1)
    const [mensagem, opcoes] = toastMock.warning.mock.calls[0] as [string, { duration: number }]
    expect(mensagem).toMatch(/Linha 3/)
    expect(opcoes.duration).toBe(Infinity)
  })

  it('remove o workspace do índice local e volta ao workspace PRÓPRIO', () => {
    handleAccessRevoked(WS_A)

    const store = useWorkspaceStore.getState()
    expect(store.workspaces.map((w) => w.id)).toEqual([WS_PROPRIO])
    expect(store.currentWorkspaceId).toBe(WS_PROPRIO)
    expect(navegou).toEqual(['/dashboard'])
  })

  it('descarta TODO o cache com prefixo [ws, wsId] e preserva o dos outros', () => {
    queryClient.setQueryData(['ws', WS_A, 'members'], [{ id: 'm-1' }])
    queryClient.setQueryData(['ws', WS_A, 'invitations'], [{ id: 'i-1' }])
    queryClient.setQueryData(['ws', WS_PROPRIO, 'members'], [{ id: 'm-9' }])

    handleAccessRevoked(WS_A)

    expect(queryClient.getQueryData(['ws', WS_A, 'members'])).toBeUndefined()
    expect(queryClient.getQueryData(['ws', WS_A, 'invitations'])).toBeUndefined()
    expect(queryClient.getQueryData(['ws', WS_PROPRIO, 'members'])).toEqual([{ id: 'm-9' }])
  })

  it('uma rajada de 403 do mesmo workspace produz UM aviso, não N', () => {
    handleAccessRevoked(WS_A)
    handleAccessRevoked(WS_A)
    handleAccessRevoked(WS_A)

    expect(toastMock.warning).toHaveBeenCalledTimes(1)
  })

  it('sem outro workspace, limpa o contexto em vez de deixar um id morto selecionado', () => {
    useWorkspaceStore.setState({
      currentWorkspaceId: WS_A,
      currentRoleLabel: 'view',
      workspaces: [{ id: WS_A, name: 'Linha 3', role: 'view' }],
    })

    handleAccessRevoked(WS_A)

    expect(useWorkspaceStore.getState().currentWorkspaceId).toBeNull()
    expect(navegou).toEqual(['/dashboard'])
  })

  it('reinserir o workspace no índice local não devolve acesso: é cache de UI', () => {
    handleAccessRevoked(WS_A)

    // O usuário adultera o store persistido e recarrega.
    useWorkspaceStore.getState().setWorkspaces([
      { id: WS_A, name: 'Linha 3', role: 'owner' },
      { id: WS_PROPRIO, name: 'Workspace de Edu', role: 'owner' },
    ])
    useWorkspaceStore.getState().selectWorkspace(WS_A)

    // Nada aqui concede acesso: o servidor resolve o papel de novo a cada
    // request e responde 403 (há request spec provando isso). O que o cliente
    // faz é reexecutar a rotina no próximo 403 — e o índice some de novo.
    resetAccessRevokedState()
    handleAccessRevoked(WS_A)

    expect(useWorkspaceStore.getState().workspaces.map((w) => w.id)).toEqual([WS_PROPRIO])
  })
})
