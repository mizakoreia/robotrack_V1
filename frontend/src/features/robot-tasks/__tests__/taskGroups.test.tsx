import { describe, expect, it, vi, beforeEach, afterEach } from 'vitest'
import { render, screen, waitFor, fireEvent } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { MemoryRouter, Routes, Route } from 'react-router-dom'
import { RobotRouteKey } from '@/app/pages/RobotRouteKey'
import { groupByCategory, groupLetter } from '@/features/robot-tasks/taskGroups'
import { robotTasksApi, type TaskDTO } from '@/lib/api/endpoints'
import { useWorkspaceStore } from '@/store/workspaceStore'
import { safeStorage } from '@/lib/safeStorage'

// robot-task-grouping G1 — agrupamento por categoria e colapso.
function task(over: Partial<TaskDTO>): TaskDTO {
  return {
    id: 'x', robot_id: 'r1', cat: 'A. Hardware', desc: 'T', weight: 1, progress: 0,
    status: 'Pendente', position: 0, lock_version: 0, updated_at: '', assignees: [],
    advances_count: 0, last_comment: null, contributors: [], last_advance: null, ...over,
  }
}

describe('groupByCategory (D-TG-1)', () => {
  it('categorias não contíguas viram UM grupo só, na ordem de 1ª aparição', () => {
    const groups = groupByCategory([
      task({ id: 'a', cat: 'A' }),
      task({ id: 'b', cat: 'B' }),
      task({ id: 'c', cat: 'A' }),
    ])
    expect(groups.map((g) => g.cat)).toEqual(['A', 'B'])
    expect(groups[0].tasks.map((t) => t.id)).toEqual(['a', 'c'])
    expect(groups[1].tasks.map((t) => t.id)).toEqual(['b'])
  })
})

describe('groupLetter (D-TG-2)', () => {
  it('índice vira A/B/C… e cai para número acima de 26', () => {
    expect(groupLetter(0)).toBe('A')
    expect(groupLetter(1)).toBe('B')
    expect(groupLetter(25)).toBe('Z')
    expect(groupLetter(26)).toBe('27')
  })
})

const HEADER = { id: 'r1', cell_id: 'c1', name: 'R01', application: 'Solda Ponto', weighted_progress: { value: 40, metric: 'weighted' as const, label: 'Progresso ponderado' } }

function renderPage() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false, gcTime: 0 } } })
  return render(
    <QueryClientProvider client={client}>
      <MemoryRouter initialEntries={['/robo/r1']}>
        <Routes>
          <Route path="/robo/:id" element={<RobotRouteKey />} />
        </Routes>
      </MemoryRouter>
    </QueryClientProvider>,
  )
}

describe('categorias colapsáveis (D-TG-2/3/4/5)', () => {
  beforeEach(() => {
    useWorkspaceStore.setState({ workspaces: [{ id: 'betim', name: 'Betim', role: 'owner' }], currentWorkspaceId: 'betim', currentRoleLabel: 'owner' })
    vi.spyOn(robotTasksApi, 'getRobot').mockImplementation((rid) => Promise.resolve({ ...HEADER, id: rid, name: rid.toUpperCase() }))
    vi.spyOn(robotTasksApi, 'listForRobot').mockResolvedValue([
      task({ id: 'a', cat: 'Hardware', desc: 'Fixar base', status: 'Pendente' }),
      task({ id: 'b', cat: 'Rede', desc: 'Configurar IP', status: 'Concluído', progress: 100 }),
    ])
    safeStorage.set('local', 'rt.taskgroups.v2.r1', '[]') // nada aberto → tudo fechado
  })
  afterEach(() => vi.restoreAllMocks())

  it('cabeçalho tem prefixo A./B. e contagem; começa FECHADO', async () => {
    renderPage()
    const h = await screen.findByRole('button', { name: /A\..*Hardware.*\(1\)/s })
    expect(h).toHaveAttribute('aria-expanded', 'false')
    expect(screen.getByRole('button', { name: /B\..*Rede.*\(1\)/s })).toBeInTheDocument()
    // fechado por padrão: a tarefa não está no DOM
    expect(screen.queryByText('Fixar base')).not.toBeInTheDocument()
  })

  it('expandir mostra as tarefas do grupo e persiste a ABERTA por robô', async () => {
    renderPage()
    const h = await screen.findByRole('button', { name: /A\..*Hardware/s })
    expect(screen.queryByText('Fixar base')).not.toBeInTheDocument()

    fireEvent.click(h)
    await waitFor(() => expect(screen.getByText('Fixar base')).toBeInTheDocument())
    expect(h).toHaveAttribute('aria-expanded', 'true')
    // a outra categoria segue fechada
    expect(screen.queryByText('Configurar IP')).not.toBeInTheDocument()
    // persistiu a aberta
    expect(safeStorage.get('local', 'rt.taskgroups.v2.r1')).toContain('Hardware')
  })
})
