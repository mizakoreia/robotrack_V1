import { describe, it, expect, beforeEach } from 'vitest'
import { render, screen, act, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider, useQuery } from '@tanstack/react-query'
import { RealtimeClient } from '../connection'
import { catalogKeys } from '../../api/catalogKeys'
import { useRealtimeStore } from '../../../store/realtimeStore'
import type { RealtimeEnvelope } from '../eventMap'
import type { WorkspaceSyncResult } from '../../api/endpoints'

// realtime-collaboration 9.2 (§3.5, §Req. invalidação) — a prova ponta a ponta: a
// sessão A registra 40→60 e a sessão B vê 60 em ≤2s SEM recarregar. É o cenário
// que o plano anterior tinha perdido. Padrão do repo: integração RTL com dois
// QueryClients simulando duas sessões (o harness Playwright não existe —
// divergência registrada no EXECUCAO).
const WS = 'w1'
const ROBOT = 'r1'
let serverProgress = 40

// Barramento de Cable compartilhado: um broadcast chega a todos os consumers
// inscritos (é o que o Redis faz entre as conexões reais).
class Bus {
  subs = new Set<(d: unknown) => void>()
  broadcast(d: unknown) {
    for (const s of [...this.subs]) s(d)
  }
}
function busConsumer(bus: Bus) {
  return {
    subscriptions: {
      create: (_params: Record<string, unknown>, mixin: { connected?: () => void; received?: (d: unknown) => void }) => {
        const handler = (d: unknown) => mixin.received?.(d)
        bus.subs.add(handler)
        queueMicrotask(() => mixin.connected?.())
        return { unsubscribe: () => bus.subs.delete(handler) }
      },
    },
    disconnect: () => {},
  }
}

function Screen({ tid }: { tid: string }) {
  const q = useQuery({
    queryKey: catalogKeys.robotTasks(WS, ROBOT),
    queryFn: async () => [{ id: 't1', progress: serverProgress }],
  })
  return <span data-testid={tid}>{q.data?.[0]?.progress ?? '-'}</span>
}

function advanceEnvelope(): RealtimeEnvelope {
  return {
    v: 1, seq: 4, workspace_id: WS, type: 'task_advance.created',
    entity: { kind: 'task', id: 't1' }, scope: { project_id: 'p', cell_id: 'c', robot_id: ROBOT },
    actor_person_id: 'ana', origin_id: 'sessao-A', at: '',
  }
}

describe('Duas sessões no mesmo robô convergem (9.2)', () => {
  beforeEach(() => {
    serverProgress = 40
    useRealtimeStore.setState({ originId: 'sessao-B' }) // B tem origem própria ≠ A
  })

  it('A registra 40→60; B vê 60 em ≤2s sem recarregar', async () => {
    const bus = new Bus()
    const clientA = new QueryClient({ defaultOptions: { queries: { retry: false } } })
    const clientB = new QueryClient({ defaultOptions: { queries: { retry: false } } })

    // A conexão viva é a da sessão B (é ela que precisa convergir).
    const sessionB = new RealtimeClient({
      queryClient: clientB,
      createConsumer: () => busConsumer(bus),
      fetchTicket: async () => 'ticket-B',
      fetchSync: async (): Promise<WorkspaceSyncResult> => ({ current_seq: 0, gap: false, entity_kinds: [] }),
      wsUrl: 'ws://x/cable',
      intervalMs: 5,
      welcomeMs: 100_000,
    })
    await sessionB.connect(WS)

    render(
      <>
        <QueryClientProvider client={clientA}>
          <Screen tid="A" />
        </QueryClientProvider>
        <QueryClientProvider client={clientB}>
          <Screen tid="B" />
        </QueryClientProvider>
      </>,
    )
    await waitFor(() => expect(screen.getByTestId('B').textContent).toBe('40'))

    // Sessão A registra 40→60: sua tela aplica otimista, o servidor passa a 60, e
    // o servidor emite o envelope de avanço no barramento (origem = sessão A).
    act(() => clientA.setQueryData(catalogKeys.robotTasks(WS, ROBOT), [{ id: 't1', progress: 60 }]))
    serverProgress = 60
    act(() => bus.broadcast(advanceEnvelope()))

    // B (origem ≠ A) não descarta: invalida, refetcha e converge para 60.
    await waitFor(() => expect(screen.getByTestId('B').textContent).toBe('60'), { timeout: 2000 })
    expect(screen.getByTestId('A').textContent).toBe('60')

    sessionB.disconnect()
  })
})
