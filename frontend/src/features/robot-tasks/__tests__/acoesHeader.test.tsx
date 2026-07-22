import { describe, expect, it, vi, beforeEach, afterEach } from 'vitest'
import { render, screen, waitFor, fireEvent, within } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { MemoryRouter, Routes, Route } from 'react-router-dom'
import { Toaster } from 'sonner'
import { RobotRouteKey } from '@/app/pages/RobotRouteKey'
import { robotTasksApi, hierarchyApi, type TaskDTO } from '@/lib/api/endpoints'
import { useWorkspaceStore } from '@/store/workspaceStore'

// robot-task-table 4.4/4.5 (§4.1, D-RTT-9) — o gating de `view` na tela (controles
// FORA do DOM, não desabilitados), a coluna Ações (editar/excluir + confirmação) e
// a sincronização que informa a contagem e reseta o filtro para "Todos".

const HEADER = {
  id: 'r1', cell_id: 'c1', name: 'R01', application: 'Solda Ponto',
  weighted_progress: { value: 40, metric: 'weighted' as const, label: 'Progresso ponderado' },
}
function task(over: Partial<TaskDTO> = {}): TaskDTO {
  return {
    id: 't1', robot_id: 'r1', cat: 'A. Hardware', desc: 'Fixar base', weight: 1,
    progress: 0, status: 'Pendente', position: 0, lock_version: 3, updated_at: '',
    assignees: [], advances_count: 0, last_comment: null, contributors: [], last_advance: null, ...over,
  }
}
let serverTasks: TaskDTO[] = []

function renderPage() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } })
  render(
    <QueryClientProvider client={client}>
      <MemoryRouter initialEntries={['/robo/r1']}>
        <Routes>
          <Route path="/robo/:id" element={<RobotRouteKey />} />
        </Routes>
      </MemoryRouter>
      <Toaster />
    </QueryClientProvider>,
  )
  return client
}

function setRole(role: 'owner' | 'edit' | 'view') {
  useWorkspaceStore.setState({
    workspaces: [{ id: 'betim', name: 'Betim', role }],
    currentWorkspaceId: 'betim',
    currentRoleLabel: role,
  })
}

beforeEach(() => {
  serverTasks = [task()]
  vi.spyOn(robotTasksApi, 'getRobot').mockResolvedValue(HEADER)
  vi.spyOn(robotTasksApi, 'listForRobot').mockImplementation(() => Promise.resolve(serverTasks))
})
afterEach(() => vi.restoreAllMocks())

describe('gating de papel (4.4, D-RTT-9)', () => {
  it('view: sem coluna Ações, sem Adicionar/Sincronizar, sem ±, status é Badge (sem select)', async () => {
    setRole('view')
    renderPage()
    await screen.findByText('Fixar base')

    expect(screen.queryByRole('columnheader', { name: 'Ações' })).toBeNull()
    expect(screen.queryByRole('button', { name: 'Adicionar tarefa' })).toBeNull()
    expect(screen.queryByRole('button', { name: 'Sincronizar tarefas-base' })).toBeNull()
    expect(screen.queryByLabelText('+10%')).toBeNull()
    expect(screen.queryByLabelText('−10%')).toBeNull()
    // status estático: não há <select> de status
    expect(screen.queryByLabelText('Status de Fixar base')).toBeNull()
  })

  it('owner: coluna Ações, Adicionar e Sincronizar presentes', async () => {
    setRole('owner')
    renderPage()
    await screen.findByText('Fixar base')
    expect(screen.getByRole('columnheader', { name: 'Ações' })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Adicionar tarefa' })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Sincronizar tarefas-base' })).toBeInTheDocument()
  })
})

describe('coluna Ações (4.3)', () => {
  it('editar descrição atualiza a linha sem reload', async () => {
    setRole('edit')
    const update = vi.spyOn(robotTasksApi, 'update').mockImplementation((_id, body) => {
      serverTasks = [task({ desc: body.desc })]
      return Promise.resolve(serverTasks[0])
    })
    renderPage()
    await screen.findByText('Fixar base')

    fireEvent.click(screen.getByRole('button', { name: 'Editar a descrição de Fixar base' }))
    const input = await screen.findByLabelText('Descrição')
    fireEvent.change(input, { target: { value: 'Fixar base do robô' } })
    fireEvent.click(screen.getByRole('button', { name: 'Salvar' }))

    await waitFor(() => expect(update).toHaveBeenCalledWith('t1', { desc: 'Fixar base do robô', lock_version: 3 }))
    await waitFor(() => expect(screen.getByText('Fixar base do robô')).toBeInTheDocument())
  })

  it('excluir exige confirmação e remove a linha', async () => {
    setRole('edit')
    const remove = vi.spyOn(robotTasksApi, 'remove').mockImplementation(() => {
      serverTasks = []
      return Promise.resolve(undefined as never)
    })
    renderPage()
    await screen.findByText('Fixar base')

    fireEvent.click(screen.getByRole('button', { name: 'Excluir Fixar base' }))
    // diálogo de confirmação
    const dialog = await screen.findByRole('dialog', { name: 'Excluir tarefa' })
    fireEvent.click(within(dialog).getByRole('button', { name: 'Excluir' }))

    await waitFor(() => expect(remove).toHaveBeenCalledWith('t1'))
    await waitFor(() => expect(screen.queryByText('Fixar base')).toBeNull())
  })
})

describe('sincronizar tarefas-base (4.2, §2.6)', () => {
  it('informa a contagem e reseta o filtro para Todos', async () => {
    setRole('owner')
    vi.spyOn(hierarchyApi, 'syncRobotTaskTemplates').mockImplementation(() => {
      serverTasks = [task(), task({ id: 't2', desc: 'Nova', status: 'Pendente' })]
      return Promise.resolve({ addedCount: 7 })
    })
    renderPage()
    await screen.findByText('Fixar base')

    // filtro em "Concluídos" para provar o reset
    const tablist = screen.getByRole('tablist', { name: 'Filtro de tarefas' })
    fireEvent.click(within(tablist).getByRole('tab', { name: 'Concluídos' }))

    fireEvent.click(screen.getByRole('button', { name: 'Sincronizar tarefas-base' }))
    await screen.findByText('7 tarefas adicionadas')
    await waitFor(() =>
      expect(within(screen.getByRole('tablist', { name: 'Filtro de tarefas' })).getByRole('tab', { name: 'Todos' }))
        .toHaveAttribute('aria-selected', 'true'),
    )
    // a linha nova é visível (o filtro não a esconde)
    expect(await screen.findByText('Nova')).toBeInTheDocument()
  })
})
