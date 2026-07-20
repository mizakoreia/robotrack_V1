import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import type { AxiosRequestConfig, AxiosResponse } from 'axios'
import { apiClient } from '../client'
import { workspacesApi } from '../endpoints'
import { useWorkspaceStore } from '../../../store/workspaceStore'

// workspace-tenancy 6.3 / D9: o cliente envia SÓ o `X-Workspace-Id` (um id) do
// workspace corrente; o papel é rótulo do servidor e nunca trafega de volta.

// @ts-expect-error — acesso ao axios interno para instrumentar o teste
const axiosInstance = apiClient.client as { defaults: { adapter: unknown } }

function capturarRequests(registro: AxiosRequestConfig[]) {
  axiosInstance.defaults.adapter = async (config: AxiosRequestConfig) => {
    registro.push(config)
    return {
      data: [],
      status: 200,
      statusText: '200',
      headers: {},
      config,
    } as AxiosResponse
  }
}

describe('contexto de tenant no cliente', () => {
  let adapterOriginal: unknown

  beforeEach(() => {
    adapterOriginal = axiosInstance.defaults.adapter
    localStorage.clear()
    useWorkspaceStore.getState().clear()
  })

  afterEach(() => {
    axiosInstance.defaults.adapter = adapterOriginal
    useWorkspaceStore.getState().clear()
    localStorage.clear()
  })

  it('envia X-Workspace-Id quando há workspace corrente', async () => {
    const registro: AxiosRequestConfig[] = []
    capturarRequests(registro)
    useWorkspaceStore.setState({
      workspaces: [{ id: 'WS-A', name: 'A', role: 'owner' }],
    })
    useWorkspaceStore.getState().selectWorkspace('WS-A')

    await workspacesApi.list()

    expect(registro[0].headers?.['X-Workspace-Id']).toBe('WS-A')
  })

  it('não envia X-Workspace-Id quando nenhum workspace foi escolhido', async () => {
    const registro: AxiosRequestConfig[] = []
    capturarRequests(registro)

    await workspacesApi.list()

    expect(registro[0].headers?.['X-Workspace-Id']).toBeUndefined()
  })

  it('persiste apenas o id, nunca o papel (papel é rótulo do servidor)', () => {
    useWorkspaceStore.setState({ workspaces: [{ id: 'WS-A', name: 'A', role: 'view' }] })
    useWorkspaceStore.getState().selectWorkspace('WS-A')

    const persistido = JSON.parse(localStorage.getItem('workspace') || '{}')
    expect(persistido.state.currentWorkspaceId).toBe('WS-A')
    expect(persistido.state.currentRoleLabel).toBeUndefined()
    expect(persistido.state.workspaces).toBeUndefined()
  })

  it('o papel corrente é derivado da lista do servidor, como rótulo', () => {
    useWorkspaceStore.getState().setWorkspaces([{ id: 'WS-A', name: 'A', role: 'view' }])
    useWorkspaceStore.getState().selectWorkspace('WS-A')
    expect(useWorkspaceStore.getState().currentRoleLabel).toBe('view')
  })
})
