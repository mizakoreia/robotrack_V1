import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'
import { render, screen, waitFor, fireEvent, cleanup } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import type { ReactNode } from 'react'
import { NotificationCenter } from '../NotificationCenter'
import type { NotificationDTO } from '@/lib/api/endpoints'
import { useWorkspaceStore } from '@/store/workspaceStore'

const navigate = vi.fn()
vi.mock('react-router-dom', () => ({ useNavigate: () => navigate }))

const toastWarning = vi.fn()
vi.mock('sonner', () => ({ toast: { warning: (...a: unknown[]) => toastWarning(...a) } }))

const listMock = vi.fn()
const markReadMock = vi.fn(async () => ({}))
vi.mock('@/lib/api/endpoints', () => ({
  notificationsApi: {
    list: () => listMock(),
    markRead: (id: string) => markReadMock(id),
    markAllRead: vi.fn(async () => ({ ok: true })),
  },
}))

const notif = (over: Partial<NotificationDTO>): NotificationDTO => ({
  id: over.id!,
  type: over.type ?? 'progress',
  msg: over.msg ?? 'mensagem',
  author_name_snapshot: 'Bruno',
  recorded_at: '',
  created_at: '',
  ts_local: '23/07 14:03',
  read: over.read ?? false,
  read_at: null,
  ctx: over.ctx ?? { project_id: 'p', cell_id: 'c', robot_id: 'r1', task_id: 't1' },
})

let qc: QueryClient
const wrap = ({ children }: { children: ReactNode }) => <QueryClientProvider client={qc}>{children}</QueryClientProvider>

beforeEach(() => {
  navigate.mockClear()
  toastWarning.mockClear()
  markReadMock.mockClear()
  qc = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  useWorkspaceStore.setState({ currentWorkspaceId: 'W1' })
  listMock.mockReset().mockResolvedValue([
    notif({ id: 'a', read: false, msg: 'nova A' }),
    notif({ id: 'b', read: false, msg: 'nova B' }),
    notif({ id: 'c', read: true, msg: 'lida C' }),
  ])
})

describe('NotificationCenter (6.4)', () => {
  it('badge deriva a contagem de não-lidas (2 de 3)', async () => {
    render(<NotificationCenter />, { wrapper: wrap })
    await waitFor(() => expect(screen.getByText('nova A')).toBeInTheDocument())
    expect(screen.getByTestId('unread-badge').textContent).toContain('2 não lidas')
  })

  it('clicar num item não lido marca como lida e navega', async () => {
    render(<NotificationCenter />, { wrapper: wrap })
    await waitFor(() => expect(screen.getByText('nova A')).toBeInTheDocument())
    fireEvent.click(screen.getByText('nova A').closest('button')!)
    expect(navigate).toHaveBeenCalledWith('/robo/r1?tarefa=t1')
    await waitFor(() => expect(markReadMock).toHaveBeenCalledWith('a'))
  })

  it('item com ctx quebrado (robot_id nulo) avisa e NÃO navega (sem tela branca)', async () => {
    listMock.mockResolvedValue([
      notif({ id: 'x', read: false, msg: 'quebrada', ctx: { project_id: null, cell_id: null, robot_id: null, task_id: null } }),
    ])
    render(<NotificationCenter />, { wrapper: wrap })
    await waitFor(() => expect(screen.getByText('quebrada')).toBeInTheDocument())
    fireEvent.click(screen.getByText('quebrada').closest('button')!)
    expect(toastWarning).toHaveBeenCalled()
    expect(navigate).not.toHaveBeenCalled()
  })

  it('estado vazio', async () => {
    listMock.mockResolvedValue([])
    render(<NotificationCenter />, { wrapper: wrap })
    await waitFor(() => expect(screen.getByText('Nenhuma notificação por aqui.')).toBeInTheDocument())
  })

  afterEach(() => cleanup())
})
