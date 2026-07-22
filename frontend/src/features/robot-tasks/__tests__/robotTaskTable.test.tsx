import { describe, expect, it, vi, beforeEach, afterEach } from 'vitest'
import { render, screen, waitFor, fireEvent, within } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { MemoryRouter, Routes, Route, useNavigate } from 'react-router-dom'
import { RobotRouteKey } from '@/app/pages/RobotRouteKey'
import { applyFilter } from '@/features/robot-tasks/filterStore'
import { robotTasksApi, type TaskDTO } from '@/lib/api/endpoints'
import { useWorkspaceStore } from '@/store/workspaceStore'

// robot-task-table 1.5/1.6 (§3.5, D-RTT-1/2) — derivação do filtro por status e o
// reset na navegação (A→B→A mostra "Todos").
function task(over: Partial<TaskDTO>): TaskDTO {
  return {
    id: 'x', robot_id: 'r1', cat: 'A. Hardware', desc: 'T', weight: 1, progress: 0,
    status: 'Pendente', position: 0, lock_version: 0, updated_at: '', assignees: [],
    advances_count: 0, last_comment: null, contributors: [], last_advance: null, ...over,
  }
}

describe('applyFilter (D-RTT-2)', () => {
  const tasks = [
    task({ id: 'a', status: 'Pendente' }),
    task({ id: 'b', status: 'Em Andamento' }),
    task({ id: 'c', status: 'Concluído' }),
    task({ id: 'd', status: 'N/A' }),
  ]
  it('Pendentes = Pendente + Em Andamento (sem N/A, sem Concluído)', () => {
    expect(applyFilter(tasks, 'pending').map((t) => t.id)).toEqual(['a', 'b'])
  })
  it('Concluídos = só Concluído', () => {
    expect(applyFilter(tasks, 'done').map((t) => t.id)).toEqual(['c'])
  })
  it('Todos inclui N/A', () => {
    expect(applyFilter(tasks, 'all').map((t) => t.id)).toEqual(['a', 'b', 'c', 'd'])
  })
})

function Harness() {
  const navigate = useNavigate()
  return (
    <>
      <button onClick={() => navigate('/robo/r2')}>ir r2</button>
      <button onClick={() => navigate('/robo/r1')}>ir r1</button>
      <Routes>
        <Route path="/robo/:id" element={<RobotRouteKey />} />
      </Routes>
    </>
  )
}

const HEADER = { id: 'r1', cell_id: 'c1', name: 'R01', application: 'Solda Ponto', weighted_progress: { value: 40, metric: 'weighted' as const, label: 'Progresso ponderado' } }

beforeEach(() => {
  useWorkspaceStore.setState({ workspaces: [{ id: 'betim', name: 'Betim', role: 'owner' }], currentWorkspaceId: 'betim', currentRoleLabel: 'owner' })
  vi.spyOn(robotTasksApi, 'getRobot').mockImplementation((rid) => Promise.resolve({ ...HEADER, id: rid, name: rid.toUpperCase() }))
  vi.spyOn(robotTasksApi, 'listForRobot').mockResolvedValue([
    task({ id: 'a', cat: 'A. Hardware', desc: 'Fixar base', status: 'Pendente' }),
    task({ id: 'b', cat: 'B. Software', desc: 'Carregar programa', status: 'Concluído', progress: 100 }),
  ])
})
afterEach(() => vi.restoreAllMocks())

describe('RobotTaskTablePage — reset de filtro na navegação (D-RTT-1)', () => {
  it('escolher "Pendentes" no robô A, ir ao B e voltar ao A mostra "Todos"', async () => {
    const client = new QueryClient({ defaultOptions: { queries: { retry: false, gcTime: 0 } } })
    render(
      <QueryClientProvider client={client}>
        <MemoryRouter initialEntries={['/robo/r1']}>
          <Harness />
        </MemoryRouter>
      </QueryClientProvider>,
    )

    const tablist = await screen.findByRole('tablist', { name: 'Filtro de tarefas' })
    fireEvent.click(within(tablist).getByRole('tab', { name: 'Pendentes' }))
    expect(within(tablist).getByRole('tab', { name: 'Pendentes' })).toHaveAttribute('aria-selected', 'true')

    fireEvent.click(screen.getByRole('button', { name: 'ir r2' }))
    await waitFor(() => expect(screen.getByRole('heading', { name: 'R2' })).toBeInTheDocument())
    fireEvent.click(screen.getByRole('button', { name: 'ir r1' }))
    await waitFor(() => expect(screen.getByRole('heading', { name: 'R1' })).toBeInTheDocument())

    // voltou ao A: filtro resetado
    const tl = screen.getByRole('tablist', { name: 'Filtro de tarefas' })
    expect(within(tl).getByRole('tab', { name: 'Todos' })).toHaveAttribute('aria-selected', 'true')
  })

  it('agrupa por categoria com separador (uma vez por grupo)', async () => {
    const client = new QueryClient({ defaultOptions: { queries: { retry: false, gcTime: 0 } } })
    render(
      <QueryClientProvider client={client}>
        <MemoryRouter initialEntries={['/robo/r1']}>
          <Routes>
            <Route path="/robo/:id" element={<RobotRouteKey />} />
          </Routes>
        </MemoryRouter>
      </QueryClientProvider>,
    )
    expect(await screen.findByText('Fixar base')).toBeInTheDocument()
    expect(screen.getByText('A. Hardware')).toBeInTheDocument()
    expect(screen.getByText('B. Software')).toBeInTheDocument()
  })
})
