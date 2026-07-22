import { describe, expect, it, vi, beforeEach, afterEach } from 'vitest'
import { render, screen, waitFor, fireEvent } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { MemoryRouter, Routes, Route } from 'react-router-dom'
import { RobotRouteKey } from '@/app/pages/RobotRouteKey'
import { robotTasksApi, taskAdvancesApi, type TaskDTO } from '@/lib/api/endpoints'
import { useWorkspaceStore } from '@/store/workspaceStore'

// robot-task-table 7.1 (§3.5) — render ÚNICA por mutação: confirmar um avanço numa
// linha NÃO re-renderiza as linhas não afetadas. A prova é o `structuralSharing` do
// React Query (mantém a referência das tarefas inalteradas) + `memo` na linha. Aqui
// a StatusCell é substituída por um contador de render POR tarefa: após avançar a
// linha A, a StatusCell da linha B não deve re-renderizar.

const renders: Record<string, number> = {}
vi.mock('@/features/robot-tasks/StatusCell', () => ({
  STATUS_COLOR: {},
  StatusCell: ({ task }: { task: TaskDTO }) => {
    renders[task.id] = (renders[task.id] ?? 0) + 1
    return <span>{task.status}</span>
  },
}))

const HEADER = {
  id: 'r1', cell_id: 'c1', name: 'R01', application: 'Solda Ponto',
  weighted_progress: { value: 40, metric: 'weighted' as const, label: 'Progresso ponderado' },
}
function task(over: Partial<TaskDTO> = {}): TaskDTO {
  return {
    id: 't', robot_id: 'r1', cat: 'A. Hardware', desc: 'T', weight: 1, progress: 40,
    status: 'Em Andamento', position: 0, lock_version: 0, updated_at: '', assignees: [],
    advances_count: 0, last_comment: null, contributors: [], last_advance: null, ...over,
  }
}
let serverTasks: TaskDTO[] = []

beforeEach(() => {
  for (const k of Object.keys(renders)) delete renders[k]
  serverTasks = [
    task({ id: 'A', desc: 'Tarefa A', progress: 40, lock_version: 0 }),
    task({ id: 'B', desc: 'Tarefa B', progress: 40, lock_version: 0 }),
  ]
  useWorkspaceStore.setState({
    workspaces: [{ id: 'betim', name: 'Betim', role: 'owner' }],
    currentWorkspaceId: 'betim', currentRoleLabel: 'owner',
  })
  vi.spyOn(robotTasksApi, 'getRobot').mockResolvedValue(HEADER)
  vi.spyOn(robotTasksApi, 'listForRobot').mockImplementation(() => Promise.resolve(serverTasks.map((t) => ({ ...t }))))
})
afterEach(() => vi.restoreAllMocks())

it('avançar a linha A não re-renderiza a linha B (§7.1)', async () => {
  const create = vi.spyOn(taskAdvancesApi, 'create').mockImplementation((_id, body) => {
    const b = body as { progress: number }
    // só A muda; B permanece byte-idêntico (structuralSharing preserva a ref)
    serverTasks = [
      task({ id: 'A', desc: 'Tarefa A', progress: b.progress, lock_version: 1 }),
      task({ id: 'B', desc: 'Tarefa B', progress: 40, lock_version: 0 }),
    ]
    return Promise.resolve({ advance: {}, task: serverTasks[0], replay: false } as never)
  })
  const client = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } })
  render(
    <QueryClientProvider client={client}>
      <MemoryRouter initialEntries={['/robo/r1']}>
        <Routes>
          <Route path="/robo/:id" element={<RobotRouteKey />} />
        </Routes>
      </MemoryRouter>
    </QueryClientProvider>,
  )

  await screen.findByText('Tarefa A')
  expect(renders.A).toBe(1)
  expect(renders.B).toBe(1)
  const bBefore = renders.B

  // avança a linha A: +10 (40→50), comentário obrigatório (<100), confirma
  fireEvent.click(screen.getAllByLabelText('+10%')[0])
  fireEvent.change(screen.getByLabelText(/Comentário/), { target: { value: 'passo A' } })
  fireEvent.click(screen.getByRole('button', { name: 'Registrar' }))

  await waitFor(() => expect(create).toHaveBeenCalledTimes(1))
  await waitFor(() => expect(renders.A).toBeGreaterThan(1)) // A re-renderizou (progresso mudou)
  // B NÃO re-renderizou por causa da mutação em A
  expect(renders.B).toBe(bBefore)
})
