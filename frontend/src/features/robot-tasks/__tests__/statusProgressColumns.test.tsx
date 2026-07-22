import { describe, expect, it, vi, beforeEach, afterEach } from 'vitest'
import { render, screen, waitFor, fireEvent } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { MemoryRouter, Routes, Route } from 'react-router-dom'
import { RobotRouteKey } from '@/app/pages/RobotRouteKey'
import { robotTasksApi, taskAdvancesApi, type TaskDTO } from '@/lib/api/endpoints'
import { useWorkspaceStore } from '@/store/workspaceStore'

// robot-task-table 2.4 (§2.2, §2.4, D-RTT-5/10) — as colunas de MUTAÇÃO da tabela:
// incremento duplo (+20, não +10), cancelamento sem requisição, 409 em modo status,
// status do SERVIDOR sobrepondo o rascunho, payload `status` (não `progress: 0`)
// para N/A, e a invalidação dupla (tasks + projects) do 2.3.

const HEADER = {
  id: 'r1',
  cell_id: 'c1',
  name: 'R01',
  application: 'Solda Ponto',
  weighted_progress: { value: 40, metric: 'weighted' as const, label: 'Progresso ponderado' },
}

function task(over: Partial<TaskDTO> = {}): TaskDTO {
  return {
    id: 't1', robot_id: 'r1', cat: 'A. Hardware', desc: 'Fixar base', weight: 1,
    progress: 0, status: 'Pendente', position: 0, lock_version: 0, updated_at: '',
    assignees: [], advances_count: 0, last_comment: null, contributors: [],
    last_advance: null, ...over,
  }
}

// A "verdade do servidor" mutável: o refetch pós-invalidação lê daqui, então cada
// teste simula o avanço trocando o conteúdo ANTES de confirmar o modal.
let serverTasks: TaskDTO[] = []

function renderPage() {
  const client = new QueryClient({
    defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
  })
  render(
    <QueryClientProvider client={client}>
      <MemoryRouter initialEntries={['/robo/r1']}>
        <Routes>
          <Route path="/robo/:id" element={<RobotRouteKey />} />
        </Routes>
      </MemoryRouter>
    </QueryClientProvider>,
  )
  return client
}

beforeEach(() => {
  useWorkspaceStore.setState({
    workspaces: [{ id: 'betim', name: 'Betim', role: 'owner' }],
    currentWorkspaceId: 'betim',
    currentRoleLabel: 'owner',
  })
  vi.spyOn(robotTasksApi, 'getRobot').mockResolvedValue(HEADER)
  vi.spyOn(robotTasksApi, 'listForRobot').mockImplementation(() => Promise.resolve(serverTasks))
})
afterEach(() => vi.restoreAllMocks())

describe('coluna Status (2.1 — §2.2)', () => {
  it('escolher Concluído em 60% abre o modal 60→100, mantém a pílula, envia `status` e o servidor sobrepõe', async () => {
    serverTasks = [task({ status: 'Em Andamento', progress: 60, lock_version: 2 })]
    const create = vi.spyOn(taskAdvancesApi, 'create').mockImplementation(() => {
      serverTasks = [task({ status: 'Concluído', progress: 100, lock_version: 3 })]
      return Promise.resolve({ advance: {}, task: serverTasks[0], replay: false } as never)
    })
    const client = renderPage()
    const invalidate = vi.spyOn(client, 'invalidateQueries')

    const select = (await screen.findByLabelText('Status de Fixar base')) as HTMLSelectElement
    fireEvent.change(select, { target: { value: 'Concluído' } })

    // modal aberto com o `para%` derivado; a pílula NÃO mudou
    const dialog = screen.getByRole('dialog')
    expect(dialog).toHaveTextContent('De 60% → Para 100%')
    expect(dialog).toHaveTextContent('Novo status: Concluído')
    expect(select.value).toBe('Em Andamento')

    // a 100 o comentário é opcional — confirma direto
    fireEvent.click(screen.getByRole('button', { name: 'Registrar' }))
    await waitFor(() => expect(create).toHaveBeenCalledTimes(1))

    // payload em modo status: `status` presente, `progress` AUSENTE (§2.2 no servidor)
    expect(create.mock.calls[0][1]).toMatchObject({ status: 'Concluído', lock_version: 2 })
    expect(create.mock.calls[0][1].progress).toBeUndefined()

    // o refetch traz a verdade do servidor: pílula e leitura viram Concluído/100%
    await waitFor(() =>
      expect((screen.getByLabelText('Status de Fixar base') as HTMLSelectElement).value).toBe('Concluído'),
    )
    expect((screen.getByLabelText('Progresso da tarefa') as HTMLInputElement).value).toBe('100')

    // 2.3 (D-RTT-10) — invalidação dupla: tasks do robô E prefixo projects
    const keys = invalidate.mock.calls.map((c) => JSON.stringify(c[0]?.queryKey))
    expect(keys).toContain(JSON.stringify(['ws', 'betim', 'robot', 'r1', 'tasks']))
    expect(keys).toContain(JSON.stringify(['ws', 'betim', 'projects']))
  })

  it('escolher N/A numa tarefa Pendente e cancelar: pílula volta, nada é enviado', async () => {
    serverTasks = [task({ status: 'Pendente', progress: 0 })]
    const create = vi.spyOn(taskAdvancesApi, 'create')
    renderPage()

    const select = (await screen.findByLabelText('Status de Fixar base')) as HTMLSelectElement
    fireEvent.change(select, { target: { value: 'N/A' } })

    const dialog = screen.getByRole('dialog')
    expect(dialog).toHaveTextContent('De 0% → Para 0%')
    // abaixo de 100 o comentário é obrigatório — confirmar está bloqueado
    expect(screen.getByRole('button', { name: 'Registrar' })).toBeDisabled()

    fireEvent.click(screen.getByRole('button', { name: 'Cancelar' }))
    expect(screen.queryByRole('dialog')).toBeNull()
    expect(select.value).toBe('Pendente')
    expect(create).not.toHaveBeenCalled()
  })

  it('409 em modo status: recalcular re-deriva pela tabela-verdade e reenvia o MESMO status com uuid novo', async () => {
    serverTasks = [task({ status: 'Em Andamento', progress: 60, lock_version: 2 })]
    const create = vi
      .spyOn(taskAdvancesApi, 'create')
      .mockRejectedValueOnce({
        response: {
          status: 409,
          data: {
            error: 'conflito_de_versao',
            task: { id: 't1', progress: 70, status: 'Em Andamento', lock_version: 5 },
            latest_advance: { author_name_snapshot: 'Ana', to_progress: 70, recorded_at: '2026-01-01T00:00:00Z', comment: 'ok' },
          },
        },
      })
      .mockResolvedValueOnce({ advance: {}, task: task({ status: 'Concluído', progress: 100 }), replay: false } as never)
    renderPage()

    fireEvent.change(await screen.findByLabelText('Status de Fixar base'), { target: { value: 'Concluído' } })
    fireEvent.click(screen.getByRole('button', { name: 'Registrar' }))

    await screen.findByText('Alguém avançou esta tarefa enquanto você escrevia')
    const uuid1 = create.mock.calls[0][1].id
    fireEvent.click(screen.getByRole('button', { name: 'Recalcular a partir de 70%' }))

    // re-derivado sobre o valor novo: Concluído continua 100, `de` vira 70
    expect(screen.getByRole('dialog')).toHaveTextContent('De 70% → Para 100%')
    fireEvent.click(screen.getByRole('button', { name: 'Registrar' }))

    await waitFor(() => expect(create).toHaveBeenCalledTimes(2))
    expect(create.mock.calls[1][1]).toMatchObject({ status: 'Concluído', lock_version: 5 })
    expect(create.mock.calls[1][1].id).not.toBe(uuid1) // outro fato → outro uuid
  })
})

describe('coluna Progresso (2.2/2.3 — §2.4, D-RTT-5)', () => {
  it('dois + sem recarregar somam +20: o segundo modal abre 30→40 e persiste 40', async () => {
    serverTasks = [task({ status: 'Em Andamento', progress: 20, lock_version: 0 })]
    const create = vi.spyOn(taskAdvancesApi, 'create').mockImplementation((_id, body) => {
      const b = body as { progress: number }
      serverTasks = [task({ status: 'Em Andamento', progress: b.progress, lock_version: serverTasks[0].lock_version + 1 })]
      return Promise.resolve({ advance: {}, task: serverTasks[0], replay: false } as never)
    })
    renderPage()

    fireEvent.click(await screen.findByLabelText('+10%'))
    expect(screen.getByRole('dialog')).toHaveTextContent('De 20% → Para 30%')
    fireEvent.change(screen.getByLabelText(/Comentário/), { target: { value: 'primeiro passo' } })
    fireEvent.click(screen.getByRole('button', { name: 'Registrar' }))

    // refetch pós-invalidação: o persistido agora é 30
    await waitFor(() =>
      expect((screen.getByLabelText('Progresso da tarefa') as HTMLInputElement).value).toBe('30'),
    )

    fireEvent.click(screen.getByLabelText('+10%'))
    expect(screen.getByRole('dialog')).toHaveTextContent('De 30% → Para 40%')
    fireEvent.change(screen.getByLabelText(/Comentário/), { target: { value: 'segundo passo' } })
    fireEvent.click(screen.getByRole('button', { name: 'Registrar' }))

    await waitFor(() => expect(create).toHaveBeenCalledTimes(2))
    expect(create.mock.calls[1][1]).toMatchObject({ progress: 40, lock_version: 1 })
    await waitFor(() =>
      expect((screen.getByLabelText('Progresso da tarefa') as HTMLInputElement).value).toBe('40'),
    )
  })

  it('arrastar 30→70 e cancelar devolve o slider a 30 sem nenhuma requisição', async () => {
    serverTasks = [task({ status: 'Em Andamento', progress: 30 })]
    const create = vi.spyOn(taskAdvancesApi, 'create')
    renderPage()

    const slider = (await screen.findByLabelText('Progresso da tarefa')) as HTMLInputElement
    fireEvent.change(slider, { target: { value: '70' } })
    expect(slider.value).toBe('70')
    expect(screen.getByRole('dialog')).toHaveTextContent('De 30% → Para 70%')

    fireEvent.click(screen.getByRole('button', { name: 'Cancelar' }))
    expect(screen.queryByRole('dialog')).toBeNull()
    expect((screen.getByLabelText('Progresso da tarefa') as HTMLInputElement).value).toBe('30')
    expect(create).not.toHaveBeenCalled()
  })
})
