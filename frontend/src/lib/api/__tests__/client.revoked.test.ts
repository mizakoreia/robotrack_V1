import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'
import type { AxiosRequestConfig, AxiosResponse } from 'axios'

// workspace-invitations 5.3 / D-INV-7 — o caminho PUXADO da revogação, no
// interceptor. Prova que a detecção funciona sem ActionCable nenhum: o gatilho é
// a própria negação do servidor.
//
// A falha a caçar é a confusão entre os dois 403: `workspace_access_denied` é o
// de quem NUNCA teve acesso (id digitado errado, workspace alheio) e NÃO pode
// disparar a rotina — senão o índice local de um usuário legítimo seria apagado
// por um erro de digitação.

vi.mock('sonner', () => ({
  toast: { warning: vi.fn(), error: vi.fn(), success: vi.fn(), info: vi.fn() },
}))

import { apiClient } from '../client'
import { useAuthStore } from '../../../store/authStore'
import { useWorkspaceStore } from '../../../store/workspaceStore'
import { registerRevocationNavigator, resetAccessRevokedState } from '../../workspace/accessRevoked'

// @ts-expect-error — acesso ao axios interno para instrumentar o teste
const axiosInstance = apiClient.client as { defaults: { adapter: unknown } }

const WS_A = '11111111-1111-4111-8111-111111111111'
const WS_PROPRIO = '22222222-2222-4222-8222-222222222222'

function instalarAdapter(status: number, data: unknown) {
  axiosInstance.defaults.adapter = async (config: AxiosRequestConfig) => {
    const response = { data, status, statusText: String(status), headers: {}, config } as AxiosResponse
    if (status >= 400) {
      const erro = new Error(`Request failed with status code ${status}`) as Error & {
        response: AxiosResponse; config: AxiosRequestConfig; isAxiosError: boolean
      }
      erro.response = response
      erro.config = config
      erro.isAxiosError = true
      throw erro
    }
    return response
  }
}

describe('apiClient — 403 workspace_access_revoked dispara a rotina de revogação', () => {
  const adapterOriginal = axiosInstance.defaults.adapter

  beforeEach(() => {
    resetAccessRevokedState()
    registerRevocationNavigator(() => {})
    useAuthStore.getState().setSession('token-x', { id: 'u1' }, { remember: false })
    useWorkspaceStore.setState({
      currentWorkspaceId: WS_A,
      currentRoleLabel: 'edit',
      workspaces: [
        { id: WS_A, name: 'Linha 3', role: 'edit' },
        { id: WS_PROPRIO, name: 'Workspace de Edu', role: 'owner' },
      ],
    })
  })

  afterEach(() => {
    axiosInstance.defaults.adapter = adapterOriginal
    registerRevocationNavigator(null)
    useAuthStore.getState().clearSession()
  })

  it('remove o workspace do índice local e seleciona o próprio', async () => {
    instalarAdapter(403, { error: 'workspace_access_revoked' })

    await expect(apiClient.get('/api/v1/memberships')).rejects.toBeTruthy()

    await vi.waitFor(() => {
      expect(useWorkspaceStore.getState().workspaces.map((w) => w.id)).toEqual([WS_PROPRIO])
    })
    expect(useWorkspaceStore.getState().currentWorkspaceId).toBe(WS_PROPRIO)
  })

  it('403 workspace_access_denied NÃO dispara a rotina', async () => {
    instalarAdapter(403, { error: 'workspace_access_denied' })

    await expect(apiClient.get('/api/v1/memberships')).rejects.toBeTruthy()

    await new Promise((r) => setTimeout(r, 20))
    expect(useWorkspaceStore.getState().workspaces).toHaveLength(2)
    expect(useWorkspaceStore.getState().currentWorkspaceId).toBe(WS_A)
  })

  it('a sessão NÃO é invalidada: o usuário segue autenticado nos outros workspaces', async () => {
    instalarAdapter(403, { error: 'workspace_access_revoked' })

    await expect(apiClient.get('/api/v1/memberships')).rejects.toBeTruthy()

    await vi.waitFor(() => expect(useWorkspaceStore.getState().currentWorkspaceId).toBe(WS_PROPRIO))
    expect(useAuthStore.getState().isAuthenticated).toBe(true)
    expect(useAuthStore.getState().accessToken).toBe('token-x')
  })
})
