import 'fake-indexeddb/auto'
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { renderHook, act } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { IDBFactory } from 'fake-indexeddb'
import type { ReactNode } from 'react'
import { useRecordAdvance } from '../useRecordAdvance'
import { _resetQueueDbSingleton } from '../../../lib/offline/db'
import { listMutations } from '../../../lib/offline/queue'
import { useOfflineQueueStore } from '../../../store/offlineQueueStore'

// offline-pwa 7.2/8.5 (D7-7/D8) — a fiação do lado ESCRITA: `useRecordAdvance`
// ENFILEIRA quando offline (em vez de perder a mutação num POST sem rede) e mantém
// o caminho online intocado. É o fluxo-núcleo do produto: o operário registra +10
// no galpão sem sinal e o avanço sobrevive ao turno.

const WS = 'W1'
vi.mock('../../../store/workspaceStore', () => ({
  useWorkspaceStore: (selector: (s: { currentWorkspaceId: string }) => unknown) =>
    selector({ currentWorkspaceId: WS }),
}))

const apiCreate = vi.fn()
vi.mock('../../../lib/api/endpoints', async (original) => {
  const real = await original<typeof import('../../../lib/api/endpoints')>()
  return { ...real, taskAdvancesApi: { ...real.taskAdvancesApi, create: (...a: unknown[]) => apiCreate(...a) } }
})

function wrapper(client: QueryClient) {
  return ({ children }: { children: ReactNode }) => (
    <QueryClientProvider client={client}>{children}</QueryClientProvider>
  )
}

function setOnline(value: boolean) {
  Object.defineProperty(navigator, 'onLine', { value, configurable: true })
}

describe('useRecordAdvance — lado escrita (offline enfileira)', () => {
  beforeEach(async () => {
    globalThis.indexedDB = new IDBFactory() // banco limpo por teste
    _resetQueueDbSingleton()
    apiCreate.mockReset().mockResolvedValue({ id: 'a', task: { id: 'T1', progress: 50, status: 'Em Andamento' } })
    await useOfflineQueueStore.getState().setWorkspace(WS)
  })
  afterEach(() => setOnline(true))

  it('OFFLINE: enfileira o avanço com recorded_at do gesto, NÃO chama a API e o store reflete', async () => {
    setOnline(false)
    const { result } = renderHook(() => useRecordAdvance('R1'), { wrapper: wrapper(new QueryClient()) })

    await act(async () => {
      await result.current.mutateAsync({
        taskId: 'T1',
        id: 'adv-1',
        toProgress: 50,
        comment: 'cabo pendente',
        recordedAt: '2024-03-11T14:02:00Z',
      })
    })

    expect(apiCreate).not.toHaveBeenCalled()

    const queued = await listMutations(WS)
    expect(queued).toHaveLength(1)
    expect(queued[0].kind).toBe('advance.create')
    expect(queued[0].resource_uuid).toBe('adv-1')
    expect((queued[0].body as { progress?: number }).progress).toBe(50)
    expect(queued[0].recorded_at).toBe('2024-03-11T14:02:00Z') // honestidade temporal (D8)
    expect(queued[0].url).toBe('/api/v1/tasks/T1/advances')

    // O overlay é reativo ao store — o store tem de refletir o item na hora.
    expect(useOfflineQueueStore.getState().mutations).toHaveLength(1)
  })

  it('ONLINE: envia direto pela API e NÃO enfileira nada', async () => {
    setOnline(true)
    const { result } = renderHook(() => useRecordAdvance('R1'), { wrapper: wrapper(new QueryClient()) })

    await act(async () => {
      await result.current.mutateAsync({ taskId: 'T1', id: 'adv-2', toProgress: 70, recordedAt: '2024-03-11T14:02:00Z' })
    })

    expect(apiCreate).toHaveBeenCalledTimes(1)
    expect(await listMutations(WS)).toHaveLength(0)
  })
})
