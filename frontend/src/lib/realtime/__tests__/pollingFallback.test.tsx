import { describe, it, expect, beforeEach } from 'vitest'
import { render, screen, act, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider, useQuery } from '@tanstack/react-query'
import type { ReactNode } from 'react'
import { catalogKeys } from '../../api/catalogKeys'
import { DegradedPoller } from '../poller'
import { useRealtimeStore } from '../../../store/realtimeStore'

// realtime-collaboration 7.5 — o proxy bloqueia o WebSocket (não há consumer
// nenhum): a tela do robô AINDA atualiza, pelo polling do modo degradado. O
// padrão do repo é integração RTL (o harness Playwright de
// quality-and-accessibility não existe — divergência registrada no EXECUCAO).
const WS = 'w1'
const ROBOT = 'r1'
let serverProgress = 40

function Screen() {
  const q = useQuery({
    queryKey: catalogKeys.robotTasks(WS, ROBOT),
    queryFn: async () => [{ id: 't1', progress: serverProgress }],
  })
  return <span data-testid="p">{q.data?.[0]?.progress ?? '-'}</span>
}

describe('Fallback de polling: WS bloqueado, a tela ainda atualiza (7.5)', () => {
  beforeEach(() => {
    serverProgress = 40
    useRealtimeStore.setState({ transport: 'degraded' })
  })

  it('em degraded, o avanço de outro membro aparece sem WebSocket', async () => {
    const client = new QueryClient({ defaultOptions: { queries: { retry: false } } })
    const wrapper = ({ children }: { children: ReactNode }) => (
      <QueryClientProvider client={client}>{children}</QueryClientProvider>
    )
    render(<Screen />, { wrapper })
    await screen.findByText('40')

    const poller = new DegradedPoller({
      client,
      getTransport: () => useRealtimeStore.getState().transport,
      subscribe: (cb) => useRealtimeStore.subscribe(cb),
      activeMs: 20,
      idleMs: 60,
      idleAfterMs: 10 * 60_000,
    })
    poller.start()

    // outro membro registrou 40→55 (o servidor mudou; nenhum evento de Cable chega)
    serverProgress = 55
    await waitFor(() => expect(screen.getByTestId('p').textContent).toBe('55'), { timeout: 2000 })

    poller.stop()
    // voltar a live desliga o polling
    act(() => useRealtimeStore.setState({ transport: 'live' }))
  })
})
