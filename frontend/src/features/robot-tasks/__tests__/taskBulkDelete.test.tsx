import { describe, expect, it, vi, beforeEach, afterEach } from 'vitest'
import { render, screen, waitFor, fireEvent, within } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { MemoryRouter, Routes, Route } from 'react-router-dom'
import { RobotRouteKey } from '@/app/pages/RobotRouteKey'
import { robotTasksApi, type TaskDTO } from '@/lib/api/endpoints'
import { useWorkspaceStore } from '@/store/workspaceStore'
import { safeStorage } from '@/lib/safeStorage'

// robot-task-grouping G3 — seleção múltipla e exclusão em lote (owner-only).
function task(over: Partial<TaskDTO>): TaskDTO {
  return {
    id: 'x', robot_id: 'r1', cat: 'Hardware', desc: 'T', weight: 1, progress: 0,
    status: 'Pendente', position: 0, lock_version: 0, updated_at: '', assignees: [],
    advances_count: 0, last_comment: null, contributors: [], last_advance: null, ...over,
  }
}

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

beforeEach(() => {
  vi.spyOn(robotTasksApi, 'getRobot').mockImplementation((rid) => Promise.resolve({ ...HEADER, id: rid, name: rid.toUpperCase() }))
  vi.spyOn(robotTasksApi, 'listForRobot').mockResolvedValue([
    task({ id: 'a', cat: 'Hardware', desc: 'Fixar base' }),
    task({ id: 'b', cat: 'Hardware', desc: 'Aterrar' }),
    task({ id: 'c', cat: 'Rede', desc: 'Configurar IP' }),
  ])
  // categorias fecham por padrão; abrimos as duas para os checkboxes aparecerem.
  safeStorage.set('local', 'rt.taskgroups.v2.r1', JSON.stringify(['Hardware', 'Rede']))
})
afterEach(() => vi.restoreAllMocks())

describe('exclusão em lote (owner)', () => {
  beforeEach(() => useWorkspaceStore.setState({ workspaces: [{ id: 'betim', name: 'Betim', role: 'owner' }], currentWorkspaceId: 'betim', currentRoleLabel: 'owner' }))

  it('selecionar 2 e confirmar chama bulkRemove UMA vez com os 2 ids', async () => {
    const bulk = vi.spyOn(robotTasksApi, 'bulkRemove').mockResolvedValue({ deletedCount: 2 })
    renderPage()

    fireEvent.click(await screen.findByLabelText('Selecionar Fixar base'))
    fireEvent.click(screen.getByLabelText('Selecionar Configurar IP'))

    // barra de ação com a contagem
    expect(screen.getByText('2 tarefas selecionadas')).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: /Excluir selecionadas/ }))

    // confirma no modal
    const dialog = await screen.findByRole('dialog', { name: 'Excluir tarefas' })
    fireEvent.click(within(dialog).getByRole('button', { name: 'Excluir' }))

    await waitFor(() => expect(bulk).toHaveBeenCalledTimes(1))
    expect(bulk.mock.calls[0][0].sort()).toEqual(['a', 'c'])
  })
})

describe('não-dono não vê seleção', () => {
  it('membro edit não tem checkboxes de seleção', async () => {
    useWorkspaceStore.setState({ workspaces: [{ id: 'betim', name: 'Betim', role: 'edit' }], currentWorkspaceId: 'betim', currentRoleLabel: 'edit' })
    renderPage()
    await screen.findByText('Fixar base')
    expect(screen.queryByLabelText('Selecionar Fixar base')).toBeNull()
  })
})
