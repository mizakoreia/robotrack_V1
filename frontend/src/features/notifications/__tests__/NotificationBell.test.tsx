import { describe, it, expect, beforeEach, vi } from 'vitest'
import { render, screen, waitFor, fireEvent } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import type { ReactNode } from 'react'
import { NotificationBell } from '../NotificationBell'
import type { NotificationDTO } from '@/lib/api/endpoints'
import { useWorkspaceStore } from '@/store/workspaceStore'

// in-app-notifications 6.2 — o sino é o ponto de entrada que faltava (o
// NotificationCenter existia mas nunca fora ligado ao shell). Prova: badge com a
// contagem de não-lidas, e o clique abre o centro num popover.
vi.mock('react-router-dom', () => ({ useNavigate: () => vi.fn() }))
vi.mock('sonner', () => ({ toast: { warning: vi.fn() } }))

const listMock = vi.fn()
vi.mock('@/lib/api/endpoints', () => ({
  notificationsApi: {
    list: () => listMock(),
    markRead: vi.fn(async () => ({})),
    markAllRead: vi.fn(async () => ({ ok: true })),
  },
}))

const notif = (id: string, read: boolean): NotificationDTO => ({
  id,
  type: 'progress',
  msg: `msg ${id}`,
  author_name_snapshot: 'Bruno',
  recorded_at: '',
  created_at: '',
  ts_local: '23/07 14:03',
  read,
  read_at: null,
  ctx: { project_id: 'p', cell_id: 'c', robot_id: 'r1', task_id: 't1' },
})

let qc: QueryClient
const wrap = ({ children }: { children: ReactNode }) => <QueryClientProvider client={qc}>{children}</QueryClientProvider>

beforeEach(() => {
  qc = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  useWorkspaceStore.setState({ currentWorkspaceId: 'W1' })
  listMock.mockReset().mockResolvedValue([notif('a', false), notif('b', false), notif('c', true)])
})

describe('NotificationBell (6.2)', () => {
  it('mostra o badge com a contagem de não-lidas (2 de 3)', async () => {
    render(<NotificationBell />, { wrapper: wrap })
    await waitFor(() => expect(screen.getByTestId('bell-unread-badge')).toHaveTextContent('2'))
    expect(screen.getByRole('button', { name: /Notificações \(2 não lidas\)/ })).toBeInTheDocument()
  })

  it('clicar no sino abre o centro de notificações num popover', async () => {
    render(<NotificationBell />, { wrapper: wrap })
    await waitFor(() => expect(screen.getByTestId('bell-unread-badge')).toBeInTheDocument())
    expect(screen.queryByRole('dialog')).toBeNull()

    fireEvent.click(screen.getByRole('button', { name: /Notificações/ }))
    const dialog = await screen.findByRole('dialog', { name: 'Notificações' })
    expect(dialog).toBeInTheDocument()
    // o conteúdo do centro está lá dentro
    expect(screen.getByRole('heading', { name: /Notificações/ })).toBeInTheDocument()
  })

  it('sem não-lidas, não há badge', async () => {
    listMock.mockReset().mockResolvedValue([notif('c', true)])
    render(<NotificationBell />, { wrapper: wrap })
    await waitFor(() => expect(screen.getByRole('button', { name: 'Notificações' })).toBeInTheDocument())
    expect(screen.queryByTestId('bell-unread-badge')).toBeNull()
  })
})
