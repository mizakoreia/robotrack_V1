import { describe, expect, it, vi, beforeEach, afterEach } from 'vitest'
import { render, screen, waitFor, fireEvent, within } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { MemoryRouter, Routes, Route, useNavigate } from 'react-router-dom'
import { RobotRouteKey } from '@/app/pages/RobotRouteKey'
import {
  robotTasksApi,
  taskAdvancesApi,
  membershipsApi,
  type TaskDTO,
} from '@/lib/api/endpoints'
import { useWorkspaceStore } from '@/store/workspaceStore'

// robot-task-table 7.2/7.3 (§3.5, §4.1, D-RTT-3) — os cenários operacionais ponta a
// ponta (cada cenário nomeado é um teste) e a prova de carga: 40 tarefas em 9
// categorias carregam com UMA requisição (qualquer requisição por linha reprova).

const HEADER = {
  id: 'r1', cell_id: 'c1', name: 'R01', application: 'Solda Ponto',
  weighted_progress: { value: 40, metric: 'weighted' as const, label: 'Progresso ponderado' },
}
function task(over: Partial<TaskDTO> = {}): TaskDTO {
  return {
    id: 't', robot_id: 'r1', cat: 'A. Hardware', desc: 'T', weight: 1, progress: 0,
    status: 'Pendente', position: 0, lock_version: 0, updated_at: '', assignees: [],
    advances_count: 0, last_comment: null, contributors: [], last_advance: null, ...over,
  }
}

function setRole(role: 'owner' | 'edit' | 'view') {
  useWorkspaceStore.setState({
    workspaces: [{ id: 'betim', name: 'Betim', role }],
    currentWorkspaceId: 'betim', currentRoleLabel: role,
  })
}

let listSpy: ReturnType<typeof vi.spyOn>
let getSpy: ReturnType<typeof vi.spyOn>
let trailSpy: ReturnType<typeof vi.spyOn>
let peopleSpy: ReturnType<typeof vi.spyOn>

function mockApi(tasks: TaskDTO[]) {
  getSpy = vi.spyOn(robotTasksApi, 'getRobot').mockResolvedValue(HEADER)
  listSpy = vi.spyOn(robotTasksApi, 'listForRobot').mockResolvedValue(tasks)
  trailSpy = vi.spyOn(taskAdvancesApi, 'list').mockResolvedValue([])
  peopleSpy = vi.spyOn(membershipsApi, 'list').mockResolvedValue([] as never)
}

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

function renderAt(path = '/robo/r1', withHarness = false) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } })
  render(
    <QueryClientProvider client={client}>
      <MemoryRouter initialEntries={[path]}>
        {withHarness ? <Harness /> : (
          <Routes>
            <Route path="/robo/:id" element={<RobotRouteKey />} />
          </Routes>
        )}
      </MemoryRouter>
    </QueryClientProvider>,
  )
  return client
}

afterEach(() => vi.restoreAllMocks())

describe('E2E — cenários operacionais (7.2)', () => {
  beforeEach(() => setRole('owner'))

  it('reset de filtro A→B→A mostra "Todos"', async () => {
    getSpy = vi.spyOn(robotTasksApi, 'getRobot').mockImplementation((rid) => Promise.resolve({ ...HEADER, id: rid, name: rid.toUpperCase() }))
    listSpy = vi.spyOn(robotTasksApi, 'listForRobot').mockResolvedValue([task({ id: 'a', desc: 'Fixar', status: 'Pendente' })])
    renderAt('/robo/r1', true)

    const tablist = await screen.findByRole('tablist', { name: 'Filtro de tarefas' })
    fireEvent.click(within(tablist).getByRole('tab', { name: 'Pendentes' }))
    expect(within(tablist).getByRole('tab', { name: 'Pendentes' })).toHaveAttribute('aria-selected', 'true')

    fireEvent.click(screen.getByRole('button', { name: 'ir r2' }))
    await waitFor(() => expect(screen.getByRole('heading', { name: 'R2' })).toBeInTheDocument())
    fireEvent.click(screen.getByRole('button', { name: 'ir r1' }))
    await waitFor(() => expect(screen.getByRole('heading', { name: 'R1' })).toBeInTheDocument())

    expect(within(screen.getByRole('tablist', { name: 'Filtro de tarefas' })).getByRole('tab', { name: 'Todos' }))
      .toHaveAttribute('aria-selected', 'true')
  })

  it('aviso "Atribuir…" em progresso 30 sem responsável', async () => {
    mockApi([task({ id: 'a', desc: 'Fixar', progress: 30, status: 'Em Andamento', assignees: [] })])
    renderAt()
    expect(await screen.findByText('Atribuir…')).toBeInTheDocument()
  })

  it('contribuidor não-responsável aparece como chip secundário', async () => {
    mockApi([task({ id: 'a', desc: 'Fixar', progress: 45, status: 'Em Andamento', assignees: [{ id: 'ana', name: 'Ana' }], contributors: [{ id: 'bruno', name: 'Bruno' }] })])
    renderAt()
    expect(await screen.findByText('Ana')).toBeInTheDocument()
    expect(screen.getByText('Bruno')).toBeInTheDocument()
  })

  it('cancelamento do slider devolve o valor e não envia requisição', async () => {
    mockApi([task({ id: 'a', desc: 'Fixar', progress: 30, status: 'Em Andamento' })])
    const create = vi.spyOn(taskAdvancesApi, 'create')
    renderAt()
    const slider = await screen.findByLabelText('Progresso da tarefa')
    fireEvent.change(slider, { target: { value: '70' } })
    expect((slider as HTMLInputElement).value).toBe('70')
    fireEvent.click(screen.getByRole('button', { name: 'Cancelar' }))
    expect((screen.getByLabelText('Progresso da tarefa') as HTMLInputElement).value).toBe('30')
    expect(create).not.toHaveBeenCalled()
  })

  it('membro view não vê ações de mutação', async () => {
    setRole('view')
    mockApi([task({ id: 'a', desc: 'Fixar', progress: 30, status: 'Em Andamento' })])
    renderAt()
    await screen.findByText('Fixar')
    expect(screen.queryByRole('button', { name: 'Adicionar tarefa' })).toBeNull()
    expect(screen.queryByRole('button', { name: 'Sincronizar tarefas-base' })).toBeNull()
    expect(screen.queryByRole('columnheader', { name: 'Ações' })).toBeNull()
    expect(screen.queryByLabelText('+10%')).toBeNull()
    expect(screen.queryByLabelText('Progresso da tarefa')).toHaveAttribute('aria-disabled', 'true')
  })
})

describe('carga — 40 tarefas / 9 categorias / 1 requisição (7.3, D-RTT-3)', () => {
  beforeEach(() => setRole('owner'))

  function bigDataset() {
    const cats = Array.from({ length: 9 }, (_, i) => `${String.fromCharCode(65 + i)}. Categoria ${i + 1}`)
    // dados reais chegam AGRUPADOS por categoria (contíguos) — 9 separadores.
    return Array.from({ length: 40 }, (_, i) =>
      task({
        id: `t${i}`, desc: `Tarefa ${i}`, cat: cats[i % 9], position: i,
        progress: i % 100, status: 'Em Andamento', advances_count: 5,
      }),
    ).sort((a, b) => a.cat.localeCompare(b.cat))
  }

  it('carrega a tabela inteira com UMA requisição de tarefas (nenhuma por linha)', async () => {
    const t0 = performance.now()
    mockApi(bigDataset())
    renderAt()

    // todas as 40 linhas presentes
    await waitFor(() => expect(screen.getByText('Tarefa 39')).toBeInTheDocument())
    const tti = performance.now() - t0

    // UMA requisição para a lista; UMA para o cabeçalho; ZERO por linha
    expect(listSpy).toHaveBeenCalledTimes(1)
    expect(getSpy).toHaveBeenCalledTimes(1)
    expect(trailSpy).not.toHaveBeenCalled() // trilha só abre com o modal de histórico
    expect(peopleSpy).not.toHaveBeenCalled() // pessoas só com o modal de atribuição

    // 9 separadores de categoria (um por grupo)
    expect(screen.getAllByText(/^[A-I]\. Categoria \d$/)).toHaveLength(9)

    // sanidade de tempo até interativo (jsdom é generoso; só garante que não explode)
    expect(tti).toBeLessThan(10_000)
  })
})
