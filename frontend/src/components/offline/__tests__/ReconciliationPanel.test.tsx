import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'
import { render, screen, cleanup, fireEvent, waitFor } from '@testing-library/react'
import { ReconciliationPanel } from '../ReconciliationPanel'
import { useOfflineQueueStore } from '@/store/offlineQueueStore'
import type { QueuedMutation } from '@/lib/offline/types'

// offline-pwa 5.4 — o painel conta o fechamento transitivo no rótulo e aciona as
// duas ações. A lógica de fila (discard/fix) é mockada; aqui provamos a UI.

const discardMock = vi.fn(async () => 3)
const fixMock = vi.fn(async () => {})
vi.mock('@/lib/offline/reconcile', () => ({
  discardWithClosure: (...a: unknown[]) => discardMock(...a),
  fixAndResend: (...a: unknown[]) => fixMock(...a),
}))

const m = (over: Partial<QueuedMutation>): QueuedMutation =>
  ({
    id: over.id!,
    seq: 0,
    kind: over.kind ?? 'robot.create',
    resource_uuid: over.resource_uuid ?? over.id!,
    workspace_id: 'W1',
    method: 'POST',
    url: '/x',
    body: over.body ?? {},
    depends_on: over.depends_on ?? [],
    recorded_at: '',
    state: over.state ?? 'enqueued',
    attempts: 0,
    next_attempt_at: null,
    last_error: null,
    failure_class: over.failure_class,
  }) as QueuedMutation

beforeEach(() => {
  discardMock.mockClear()
  fixMock.mockClear()
  useOfflineQueueStore.setState({ workspaceId: 'W1', mutations: [], refresh: async () => {} })
})

describe('ReconciliationPanel (5.4)', () => {
  it('não renderiza sem itens falhos', () => {
    const { container } = render(<ReconciliationPanel />)
    expect(container).toBeEmptyDOMElement()
  })

  it('rótulo conta o fechamento transitivo: "Descartar 3 alterações"', () => {
    useOfflineQueueStore.setState({
      mutations: [
        m({ id: 'R', resource_uuid: 'R', state: 'failed', failure_class: 'permanente' }),
        m({ id: 'T', resource_uuid: 'T', depends_on: ['R'], state: 'blocked' }),
        m({ id: 'A', resource_uuid: 'A', depends_on: ['T'], state: 'blocked' }),
      ],
    })
    render(<ReconciliationPanel />)
    expect(screen.getByRole('button', { name: 'Descartar 3 alterações' })).toBeInTheDocument()
  })

  it('Descartar chama discardWithClosure com o id falho', async () => {
    useOfflineQueueStore.setState({
      mutations: [m({ id: 'R', resource_uuid: 'R', state: 'failed', failure_class: 'esgotado' })],
    })
    render(<ReconciliationPanel />)
    fireEvent.click(screen.getByRole('button', { name: 'Descartar alteração' }))
    await waitFor(() => expect(discardMock).toHaveBeenCalledWith('R'))
  })

  it('Corrigir e reenviar delega ao onFix do host quando fornecido', () => {
    const onFix = vi.fn()
    useOfflineQueueStore.setState({
      mutations: [m({ id: 'R', state: 'failed', failure_class: 'conflito' })],
    })
    render(<ReconciliationPanel onFix={onFix} />)
    fireEvent.click(screen.getByRole('button', { name: 'Corrigir e reenviar' }))
    expect(onFix).toHaveBeenCalledWith(expect.objectContaining({ id: 'R' }))
    expect(fixMock).not.toHaveBeenCalled()
  })

  afterEach(() => cleanup())
})
