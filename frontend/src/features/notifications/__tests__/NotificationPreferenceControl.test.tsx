import { describe, it, expect, beforeEach, vi } from 'vitest'
import { render, screen, waitFor, fireEvent } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import type { ReactNode } from 'react'
import { NotificationPreferenceControl } from '../NotificationPreferenceControl'
import { resolveEffective } from '../useNotificationSubscriptions'
import type { NotificationSubscriptionDTO } from '@/lib/api/endpoints'
import { useWorkspaceStore } from '@/store/workspaceStore'

// notification-preferences D-P9 — o controle seguir/silenciar: estado efetivo
// (próprio e herdado com origem), alternância otimista sem reload, a11y.
const listMock = vi.fn()
const setMock = vi.fn()
vi.mock('@/lib/api/endpoints', () => ({
  notificationSubscriptionsApi: {
    list: () => listMock(),
    set: (t: string, i: string, s: string) => setMock(t, i, s),
  },
}))

const row = (scope_type: 'project' | 'cell' | 'robot', scope_id: string, state: 'follow' | 'mute'): NotificationSubscriptionDTO => ({
  id: `${scope_type}-${scope_id}`,
  scope_type,
  scope_id,
  state,
  created_at: '',
  updated_at: '',
})

let qc: QueryClient
const wrap = ({ children }: { children: ReactNode }) => <QueryClientProvider client={qc}>{children}</QueryClientProvider>

beforeEach(() => {
  qc = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  useWorkspaceStore.setState({ currentWorkspaceId: 'W1' })
  listMock.mockReset()
  setMock.mockReset().mockResolvedValue({ id: 'x', scope_type: 'robot', scope_id: 'R1', state: 'mute', created_at: '', updated_at: '' })
})

describe('resolveEffective (mais-específico-vence)', () => {
  it('linha do robô vence linha do projeto', () => {
    const rows = [row('project', 'P1', 'mute'), row('robot', 'R1', 'follow')]
    const eff = resolveEffective(rows, [
      { type: 'robot', id: 'R1' },
      { type: 'cell', id: 'C1' },
      { type: 'project', id: 'P1' },
    ])
    expect(eff.state).toBe('follow')
    expect(eff.source).toBe('robot')
    expect(eff.inherited).toBe(false)
  })

  it('herda do ancestral quando não há linha própria', () => {
    const rows = [row('cell', 'C1', 'mute')]
    const eff = resolveEffective(rows, [
      { type: 'robot', id: 'R1' },
      { type: 'cell', id: 'C1' },
    ])
    expect(eff.state).toBe('mute')
    expect(eff.source).toBe('cell')
    expect(eff.inherited).toBe(true)
    expect(eff.own).toBe('default')
  })

  it('sem linha nenhuma = default', () => {
    const eff = resolveEffective([], [{ type: 'project', id: 'P1' }])
    expect(eff.state).toBe('default')
    expect(eff.source).toBeNull()
  })
})

describe('NotificationPreferenceControl', () => {
  it('estado próprio silenciado: aria-label indica "silenciado"', async () => {
    listMock.mockResolvedValue([row('robot', 'R1', 'mute')])
    render(<NotificationPreferenceControl scope="robot" ancestry={[{ type: 'robot', id: 'R1' }, { type: 'cell', id: 'C1' }]} />, {
      wrapper: wrap,
    })
    await waitFor(() =>
      expect(screen.getByRole('button', { name: /Notificações do robô: silenciado/ })).toBeInTheDocument(),
    )
  })

  it('estado herdado mostra a origem no rótulo', async () => {
    listMock.mockResolvedValue([row('cell', 'C1', 'mute')])
    render(<NotificationPreferenceControl scope="robot" ancestry={[{ type: 'robot', id: 'R1' }, { type: 'cell', id: 'C1' }]} />, {
      wrapper: wrap,
    })
    await waitFor(() =>
      expect(screen.getByRole('button', { name: /silenciado \(pela célula\)/ })).toBeInTheDocument(),
    )
  })

  it('escolher Silenciar envia o PUT do próprio robô e atualiza sem reload (otimista)', async () => {
    // começa no padrão; após o PUT o servidor passa a devolver a linha de mute
    listMock.mockResolvedValueOnce([]).mockResolvedValue([row('robot', 'R1', 'mute')])
    render(<NotificationPreferenceControl scope="robot" ancestry={[{ type: 'robot', id: 'R1' }, { type: 'cell', id: 'C1' }]} />, {
      wrapper: wrap,
    })
    const trigger = await screen.findByRole('button', { name: /Notificações do robô: padrão/ })
    fireEvent.click(trigger)
    const menu = await screen.findByRole('menu', { name: /Preferência de notificação do robô/ })
    fireEvent.click(screen.getByRole('menuitem', { name: /^Silenciar/ }))

    await waitFor(() => expect(setMock).toHaveBeenCalledWith('robot', 'R1', 'mute'))
    // otimista: o rótulo passa a "silenciado" sem recarregar
    await waitFor(() =>
      expect(screen.getByRole('button', { name: /Notificações do robô: silenciado/ })).toBeInTheDocument(),
    )
  })
})
