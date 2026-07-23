import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'
import { render, screen, waitFor, cleanup, act } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import type { ReactNode } from 'react'
import { useRobotTasks } from '../useRobotTasks'
import { useWorkspaceStore } from '../../../store/workspaceStore'
import { useOfflineQueueStore } from '../../../store/offlineQueueStore'
import type { QueuedMutation } from '../../../lib/offline/types'

// offline-pwa 7.4 — a sequência anti-flicker. Enfileira +10 (50→60) → o servidor
// devolve 50 (evento ao vivo/refetch) → a view CONTINUA em 60. E sobrevive ao
// REMOUNT: a sobreposição deriva da fila persistente (Zustand), não de um snapshot
// em memória — que o remount destruiria (é a armadilha que a tarefa nomeia).

const listForRobot = vi.fn()
vi.mock('../../../lib/api/endpoints', () => ({
  robotTasksApi: {
    listForRobot: (...a: unknown[]) => listForRobot(...a),
    getRobot: vi.fn(),
  },
}))

function Tela() {
  const { data } = useRobotTasks('r1')
  const t = data?.find((x) => x.id === 't1')
  return <div data-testid="prog">{t ? String((t as { progress?: number }).progress) : '—'}</div>
}

const pendingAdvance: QueuedMutation = {
  id: 'a1',
  seq: 1,
  kind: 'advance.create',
  resource_uuid: 'a1',
  workspace_id: 'W1',
  method: 'POST',
  url: '/x',
  body: { task_id: 't1', progress: 60 },
  depends_on: [],
  recorded_at: '',
  state: 'enqueued',
  attempts: 0,
  next_attempt_at: null,
  last_error: null,
}

let qc: QueryClient
function wrap({ children }: { children: ReactNode }) {
  return <QueryClientProvider client={qc}>{children}</QueryClientProvider>
}

beforeEach(() => {
  listForRobot.mockReset().mockResolvedValue([{ id: 't1', progress: 50, status: 'Pendente' }])
  qc = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  useWorkspaceStore.setState({ currentWorkspaceId: 'W1' })
  useOfflineQueueStore.setState({ workspaceId: 'W1', mutations: [pendingAdvance] })
})

describe('anti-flicker (7.4)', () => {
  it('mostra 60 (otimista), permanece 60 após refetch com 50, e após remount', async () => {
    const view = render(<Tela />, { wrapper: wrap })
    await waitFor(() => expect(screen.getByTestId('prog').textContent).toBe('60'))

    // Evento ao vivo: invalida e refetcha — o servidor ainda devolve 50.
    await qc.invalidateQueries({ queryKey: ['ws', 'W1', 'robot', 'r1', 'tasks'] })
    await waitFor(() => expect(listForRobot).toHaveBeenCalledTimes(2))
    // Nunca piscou para 50: a sobreposição foi reaplicada sobre o dado novo.
    expect(screen.getByTestId('prog').textContent).toBe('60')

    // Remonta: um snapshot em memória morreria aqui; a fila persistente não.
    view.unmount()
    render(<Tela />, { wrapper: wrap })
    await waitFor(() => expect(screen.getByTestId('prog').textContent).toBe('60'))
  })

  it('quando o avanço sai da fila (done), a view volta à verdade do servidor (50)', async () => {
    render(<Tela />, { wrapper: wrap })
    await waitFor(() => expect(screen.getByTestId('prog').textContent).toBe('60'))

    // Item drenado: sai dos pendentes → a sobreposição some.
    act(() => {
      useOfflineQueueStore.setState({ mutations: [{ ...pendingAdvance, state: 'done' }] })
    })
    await waitFor(() => expect(screen.getByTestId('prog').textContent).toBe('50'))
  })

  afterEach(() => cleanup())
})
