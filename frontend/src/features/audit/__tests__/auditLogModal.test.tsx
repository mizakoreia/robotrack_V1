import { describe, expect, it, vi, beforeEach, afterEach } from 'vitest'
import { render, screen, within } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import type { ReactNode } from 'react'
import { AuditLogModal, AUDIT_DISPLAY_LIMIT } from '@/features/audit/AuditLogModal'
import { auditLogsApi, type AuditLogDTO } from '@/lib/api/endpoints'
import { useWorkspaceStore } from '@/store/workspaceStore'

// audit-log 6.2/6.3 (§2.8, Decisão 4) — o modal: `msg`/`ts_local` verbatim do
// servidor (o cliente NÃO reformata data), ordem já vinda `ts DESC`, teto de
// exibição de 200, estados vazio e de erro. Sem controle de escrita.

function log(i: number): AuditLogDTO {
  return {
    id: `a${i}`, msg: `registro ${i}`, ts: `2026-07-01T12:00:${String(i % 60).padStart(2, '0')}Z`,
    ts_local: `01/07/2026 ${String(i).padStart(2, '0')}:00`, by_name: 'Ana', event_type: 'task_completed',
  }
}

function wrap() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  return ({ children }: { children: ReactNode }) => (
    <QueryClientProvider client={client}>{children}</QueryClientProvider>
  )
}

beforeEach(() => {
  useWorkspaceStore.setState({
    workspaces: [{ id: 'betim', name: 'Betim', role: 'owner' }],
    currentWorkspaceId: 'betim', currentRoleLabel: 'owner',
  })
})
afterEach(() => vi.restoreAllMocks())

describe('AuditLogModal (6.2/6.3)', () => {
  it('renderiza até 200 (fixture de 250), o 1º é o mais recente e os 50 mais antigos somem', async () => {
    // 250 registros JÁ em ordem ts DESC (o mais recente = registro 0)
    const rows = Array.from({ length: 250 }, (_, i) => log(i))
    vi.spyOn(auditLogsApi, 'list').mockResolvedValue(rows)
    render(<AuditLogModal open onClose={() => {}} />, { wrapper: wrap() })

    const items = await screen.findAllByRole('listitem')
    expect(items).toHaveLength(AUDIT_DISPLAY_LIMIT) // 200
    // o mais recente (registro 0) é o primeiro
    expect(within(items[0]).getByText('registro 0')).toBeInTheDocument()
    // os 50 mais antigos (200..249) não aparecem
    expect(screen.queryByText('registro 200')).toBeNull()
    expect(screen.queryByText('registro 249')).toBeNull()
    // o último exibido é o registro 199
    expect(within(items[199]).getByText('registro 199')).toBeInTheDocument()
  })

  it('usa msg e ts_local VERBATIM do servidor (não reformata data)', async () => {
    vi.spyOn(auditLogsApi, 'list').mockResolvedValue([
      { id: 'x', msg: 'Em [R-014], Ana concluiu a tarefa "T" com 100%.', ts: '2026-07-18T20:02:00Z', ts_local: '18/07/2026 17:02', by_name: 'Ana', event_type: 'task_completed' },
    ])
    render(<AuditLogModal open onClose={() => {}} />, { wrapper: wrap() })
    expect(await screen.findByText('Em [R-014], Ana concluiu a tarefa "T" com 100%.')).toBeInTheDocument()
    expect(screen.getByText('18/07/2026 17:02')).toBeInTheDocument() // ts_local do servidor, não recalculado
  })

  it('estado vazio: workspace novo mostra "nenhum registro", não lista quebrada', async () => {
    vi.spyOn(auditLogsApi, 'list').mockResolvedValue([])
    render(<AuditLogModal open onClose={() => {}} />, { wrapper: wrap() })
    expect(await screen.findByText('Nenhum registro de auditoria ainda.')).toBeInTheDocument()
    expect(screen.queryByRole('listitem')).toBeNull()
  })

  it('estado de erro: alerta acionável, distinto do vazio', async () => {
    vi.spyOn(auditLogsApi, 'list').mockRejectedValue({ response: { status: 500 } })
    render(<AuditLogModal open onClose={() => {}} />, { wrapper: wrap() })
    expect(await screen.findByRole('alert')).toHaveTextContent('Não foi possível carregar o log de auditoria.')
    expect(screen.queryByText('Nenhum registro de auditoria ainda.')).toBeNull()
  })

  it('fechado (open=false) não busca nem renderiza a lista', () => {
    const spy = vi.spyOn(auditLogsApi, 'list').mockResolvedValue([log(1)])
    render(<AuditLogModal open={false} onClose={() => {}} />, { wrapper: wrap() })
    expect(spy).not.toHaveBeenCalled()
    expect(screen.queryByText('registro 1')).toBeNull()
  })
})
