import { describe, it, expect, beforeEach } from 'vitest'
import { render, screen, fireEvent, waitFor, act } from '@testing-library/react'
import { QueryClient, QueryClientProvider, useQuery, useMutation } from '@tanstack/react-query'
import type { ReactNode } from 'react'
import { catalogKeys } from '../../api/catalogKeys'
import { qk } from '../../query/keys'
import { InvalidationQueue } from '../invalidationQueue'
import { InvalidationGate } from '../invalidationGate'
import { keysForEvent, type RealtimeEnvelope } from '../eventMap'

// realtime-collaboration 6.4 (§Req. "Evento não reverte interface otimista") — o
// teste captura o valor RENDERIZADO ao longo do tempo: falha se a sequência
// contiver 40 depois de 60 (asserção sobre estado final apenas não pega flicker).
const WS = 'w1'
const ROBOT = 'r1'

let serverProgress = 40
let resolveMut: (() => void) | null = null
let rejectMut: ((e: unknown) => void) | null = null

function thirdPartyAdvance(): RealtimeEnvelope {
  return {
    v: 1, seq: 9, workspace_id: WS, type: 'task_advance.created',
    entity: { kind: 'task', id: 't1' }, scope: { project_id: 'p', cell_id: 'c', robot_id: ROBOT },
    actor_person_id: 'outra-pessoa', origin_id: 'outra-aba', at: '',
  }
}

function Screen() {
  const q = useQuery({
    queryKey: catalogKeys.robotTasks(WS, ROBOT),
    queryFn: async () => [{ id: 't1', progress: serverProgress }],
    // pin: só refetcha por invalidação explícita (o que o gate controla), não por
    // staleness de fundo — senão a asserção sobre o otimista corre com um refetch.
    staleTime: Infinity,
  })
  const m = useMutation({
    mutationKey: qk.robot(WS, ROBOT),
    mutationFn: () => new Promise<void>((res, rej) => {
      resolveMut = res
      rejectMut = rej
    }),
    onError: () => {},
  })
  return (
    <div>
      <span data-testid="p">{q.data?.[0]?.progress ?? '-'}</span>
      <button onClick={() => m.mutate()}>go</button>
    </div>
  )
}

function setup() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } })
  const gate = new InvalidationGate(client)
  const queue = new InvalidationQueue(client, { intervalMs: 5, gate })
  const wrapper = ({ children }: { children: ReactNode }) => (
    <QueryClientProvider client={client}>{children}</QueryClientProvider>
  )
  return { client, queue, wrapper }
}

async function untilPending(client: QueryClient) {
  await waitFor(() => expect(client.getMutationCache().getAll().some((m) => m.state.status === 'pending')).toBe(true))
}

describe('Anti-flicker: evento não reverte a interface otimista (6.4)', () => {
  beforeEach(() => {
    serverProgress = 40
    resolveMut = null
    rejectMut = null
  })

  it('evento de terceiro durante o POST em voo NÃO faz a UI piscar 60→40→60', async () => {
    const { client, queue, wrapper } = setup()
    render(<Screen />, { wrapper })
    await screen.findByText('40')

    act(() => client.setQueryData(catalogKeys.robotTasks(WS, ROBOT), [{ id: 't1', progress: 60 }]))
    await waitFor(() => expect(screen.getByTestId('p').textContent).toBe('60'))

    fireEvent.click(screen.getByText('go'))
    await untilPending(client)

    act(() => queue.enqueue(keysForEvent(WS, thirdPartyAdvance())))
    await new Promise((r) => setTimeout(r, 20))
    await waitFor(() => expect(screen.getByTestId('p').textContent).toBe('60')) // nunca reverteu

    serverProgress = 60 // o POST commitou 60
    act(() => resolveMut?.())
    await waitFor(() => expect(screen.getByTestId('p').textContent).toBe('60'))
  })

  it('mutação que FALHA drena o represamento em vez de deixá-lo preso', async () => {
    const { client, queue, wrapper } = setup()
    render(<Screen />, { wrapper })
    await screen.findByText('40')
    act(() => client.setQueryData(catalogKeys.robotTasks(WS, ROBOT), [{ id: 't1', progress: 60 }]))

    fireEvent.click(screen.getByText('go'))
    await untilPending(client)
    act(() => queue.enqueue(keysForEvent(WS, thirdPartyAdvance())))
    await new Promise((r) => setTimeout(r, 20))
    expect(screen.getByTestId('p').textContent).toBe('60')

    serverProgress = 50 // a verdade do servidor
    act(() => rejectMut?.(new Error('conflito_de_versao')))
    await waitFor(() => expect(screen.getByTestId('p').textContent).toBe('50'))
  })
})
