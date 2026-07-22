import { describe, expect, it, vi, beforeEach, afterEach } from 'vitest'
import { render, screen, waitFor, fireEvent, within } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import type { ReactNode } from 'react'
import { HistoryModal } from '@/features/robot-tasks/HistoryModal'
import { AssignmentModal } from '@/features/robot-tasks/AssignmentModal'
import {
  taskAdvancesApi,
  taskAssigneesApi,
  peopleApi,
  membershipsApi,
  type TaskDTO,
  type TaskAdvanceDTO,
} from '@/lib/api/endpoints'
import { useWorkspaceStore } from '@/store/workspaceStore'

// robot-task-table 5.5 (§3.5, §2.4 item 3, D2/D8/D10/D11) — os dois modais: ordem da
// timeline por recorded_at, marcador legacy e de ausência de comentário; dedup de
// nome, seleção vazia (não cria "Não Atribuído"), e a lista sem pessoa de outro ws.

function task(over: Partial<TaskDTO> = {}): TaskDTO {
  return {
    id: 't1', robot_id: 'r1', cat: 'A. Hardware', desc: 'Fixar base', weight: 1,
    progress: 40, status: 'Em Andamento', position: 0, lock_version: 0, updated_at: '',
    assignees: [], advances_count: 0, last_comment: null, contributors: [], last_advance: null, ...over,
  }
}
function adv(over: Partial<TaskAdvanceDTO>): TaskAdvanceDTO {
  return {
    id: 'x', task_id: 't1', from_progress: 0, to_progress: 0, comment: null,
    author_name_snapshot: 'Ana', legacy: false, recorded_at: '2026-01-01T00:00:00Z',
    created_at: '2026-01-01T00:00:00Z', recorded_at_adjusted: false, synced_late: false, ...over,
  }
}

function wrap() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } })
  const Wrapper = ({ children }: { children: ReactNode }) => (
    <QueryClientProvider client={client}>{children}</QueryClientProvider>
  )
  return Wrapper
}

beforeEach(() => {
  useWorkspaceStore.setState({
    workspaces: [{ id: 'betim', name: 'Betim', role: 'owner' }],
    currentWorkspaceId: 'betim',
    currentRoleLabel: 'owner',
  })
})
afterEach(() => vi.restoreAllMocks())

describe('HistoryModal (5.1/5.2, D8)', () => {
  it('renderiza a ordem do servidor, de%→para%, marcador legacy e ausência de comentário sem herdar do vizinho', async () => {
    vi.spyOn(taskAdvancesApi, 'list').mockResolvedValue([
      adv({ id: 'a', author_name_snapshot: 'Ana', from_progress: 90, to_progress: 100, comment: null, recorded_at: '2026-02-01T14:05:00Z' }),
      adv({ id: 'b', author_name_snapshot: 'Bruno', from_progress: 40, to_progress: 90, comment: 'subiu', recorded_at: '2026-01-15T09:00:00Z' }),
      adv({ id: 'c', author_name_snapshot: 'Import', from_progress: 0, to_progress: 40, comment: 'nota', legacy: true, recorded_at: '2025-12-01T08:00:00Z' }),
    ])
    render(<HistoryModal task={task()} onClose={() => {}} />, { wrapper: wrap() })

    const items = await screen.findAllByRole('listitem')
    expect(items).toHaveLength(3)
    // ordem preservada do servidor (Ana, Bruno, Import)
    expect(items[0]).toHaveTextContent('Ana')
    expect(items[0]).toHaveTextContent('90% → 100%')
    // a entrada →100 sem comentário mostra "sem comentário", não "subiu" (do vizinho)
    expect(items[0]).toHaveTextContent('sem comentário')
    expect(items[0]).not.toHaveTextContent('subiu')
    expect(items[1]).toHaveTextContent('subiu')
    // marcador legacy só na entrada importada
    expect(within(items[2]).getByText('importado')).toBeInTheDocument()
    expect(within(items[0]).queryByText('importado')).toBeNull()
  })

  it('trilha vazia mostra estado vazio', async () => {
    vi.spyOn(taskAdvancesApi, 'list').mockResolvedValue([])
    render(<HistoryModal task={task()} onClose={() => {}} />, { wrapper: wrap() })
    expect(await screen.findByText('Nenhum avanço registrado ainda.')).toBeInTheDocument()
  })
})

describe('AssignmentModal (5.3/5.4, D10/D11)', () => {
  beforeEach(() => {
    vi.spyOn(membershipsApi, 'list').mockResolvedValue([
      { id: 'm1', person_id: 'ana', name: 'Ana' },
      { id: 'm2', person_id: 'bruno', name: 'Bruno' },
    ] as never)
  })

  it('desmarcar todos salva conjunto VAZIO (não cria "Não Atribuído", D11)', async () => {
    const replace = vi.spyOn(taskAssigneesApi, 'replace').mockResolvedValue({ added: [], removed: ['ana'] })
    render(
      <AssignmentModal robotId="r1" canEdit task={task({ assignees: [{ id: 'ana', name: 'Ana' }] })} onClose={() => {}} />,
      { wrapper: wrap() },
    )
    const ana = await screen.findByRole('checkbox', { name: 'Ana' })
    expect(ana).toBeChecked()
    fireEvent.click(ana) // desmarca
    fireEvent.click(screen.getByRole('button', { name: 'Salvar responsáveis' }))
    await waitFor(() => expect(replace).toHaveBeenCalledWith('t1', []))
  })

  it('cadastrar nome já existente MARCA a existente e informa, sem criar (D10)', async () => {
    const create = vi.spyOn(peopleApi, 'create')
    render(<AssignmentModal robotId="r1" canEdit task={task()} onClose={() => {}} />, { wrapper: wrap() })
    await screen.findByRole('checkbox', { name: 'Ana' })

    fireEvent.change(screen.getByLabelText('Cadastrar nova pessoa'), { target: { value: '  ana  ' } })
    fireEvent.click(screen.getByRole('button', { name: 'Adicionar' }))

    expect(await screen.findByText('Ana já existe — marcada.')).toBeInTheDocument()
    expect(create).not.toHaveBeenCalled()
    expect(screen.getByRole('checkbox', { name: 'Ana' })).toBeChecked()
  })

  it('nome em branco é rejeitado', async () => {
    const create = vi.spyOn(peopleApi, 'create')
    render(<AssignmentModal robotId="r1" canEdit task={task()} onClose={() => {}} />, { wrapper: wrap() })
    await screen.findByRole('checkbox', { name: 'Ana' })
    fireEvent.change(screen.getByLabelText('Cadastrar nova pessoa'), { target: { value: '   ' } })
    fireEvent.click(screen.getByRole('button', { name: 'Adicionar' }))
    expect(await screen.findByText('Informe um nome.')).toBeInTheDocument()
    expect(create).not.toHaveBeenCalled()
  })

  it('cadastrar pessoa nova cria e já entra marcada', async () => {
    vi.spyOn(peopleApi, 'create').mockResolvedValue({ id: 'caio', name: 'Caio' })
    render(<AssignmentModal robotId="r1" canEdit task={task()} onClose={() => {}} />, { wrapper: wrap() })
    await screen.findByRole('checkbox', { name: 'Ana' })
    fireEvent.change(screen.getByLabelText('Cadastrar nova pessoa'), { target: { value: 'Caio' } })
    fireEvent.click(screen.getByRole('button', { name: 'Adicionar' }))
    await waitFor(() => expect(screen.getByRole('checkbox', { name: 'Caio' })).toBeChecked())
  })

  it('view: checkboxes desabilitados, sem cadastro nem salvar', async () => {
    render(
      <AssignmentModal
        robotId="r1"
        canEdit={false}
        task={task({ assignees: [{ id: 'ana', name: 'Ana' }] })}
        onClose={() => {}}
      />,
      { wrapper: wrap() },
    )
    expect(await screen.findByRole('checkbox', { name: 'Ana' })).toBeDisabled()
    expect(screen.queryByLabelText('Cadastrar nova pessoa')).toBeNull()
    expect(screen.queryByRole('button', { name: 'Salvar responsáveis' })).toBeNull()
  })
})
