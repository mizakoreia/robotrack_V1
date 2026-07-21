import { describe, expect, it, vi, beforeEach } from 'vitest'
import { render, renderHook, act, screen, fireEvent, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import type { ReactNode } from 'react'
import { AdvanceControls } from '../AdvanceControls'
import { useAdvanceDraft } from '../useAdvanceDraft'
import { catalogKeys } from '../../../lib/api/catalogKeys'
import type { TaskDTO } from '../../../lib/api/endpoints'

// progress-advances 5.7 (§2.4, D-UI/D14/D-409) — os cinco casos concretos do
// modal de avanço, cada um nomeando o valor final esperado, não "modal
// funciona": 45→100 sem comentário, 45→60 sem comentário, dois +10 = +20,
// arrastar-e-cancelar, e o 409 que preserva o comentário e troca o uuid.

const WS = 'ws-teste'
let ROLE = 'edit'

vi.mock('../../../store/workspaceStore', () => ({
  useWorkspaceStore: (selector: (s: { currentWorkspaceId: string; currentRoleLabel: string }) => unknown) =>
    selector({ currentWorkspaceId: WS, currentRoleLabel: ROLE }),
}))

const api = { create: vi.fn() }

vi.mock('../../../lib/api/endpoints', async (original) => {
  const real = await original<typeof import('../../../lib/api/endpoints')>()
  return {
    ...real,
    taskAdvancesApi: { create: (...a: unknown[]) => api.create(...a) },
  }
})

function task(overrides: Partial<TaskDTO> = {}): TaskDTO {
  return {
    id: 't1',
    robot_id: 'r1',
    cat: 'A. Hardware',
    desc: 'Power On',
    weight: 1,
    progress: 45,
    status: 'Em Andamento',
    position: 0,
    lock_version: 0,
    updated_at: '2026-01-01T00:00:00Z',
    assignees: [],
    advances_count: 0,
    last_comment: null,
    ...overrides,
  }
}

function newClient() {
  return new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } })
}

function seed(client: QueryClient, t: TaskDTO) {
  client.setQueryData<TaskDTO[]>(catalogKeys.robotTasks(WS, 'r1'), [t])
}

function renderControls(client: QueryClient) {
  const wrapper = ({ children }: { children: ReactNode }) => (
    <QueryClientProvider client={client}>{children}</QueryClientProvider>
  )
  return render(<AdvanceControls robotId="r1" taskId="t1" />, { wrapper })
}

beforeEach(() => {
  ROLE = 'edit'
  api.create.mockReset()
})

describe('a regra dura do comentário', () => {
  it('45 → 100 sem comentário: confirmar habilitado e envia progress 100', async () => {
    const client = newClient()
    seed(client, task({ progress: 45, lock_version: 0 }))
    api.create.mockResolvedValue({ advance: {}, task: task({ progress: 100 }), replay: false })
    renderControls(client)

    fireEvent.click(screen.getByLabelText('+10%')) // abre o modal (para 55)
    const para = screen.getByLabelText('Progresso alvo (%)')
    fireEvent.change(para, { target: { value: '100' } })

    const confirmar = screen.getByRole('button', { name: 'Registrar' })
    expect(confirmar).not.toBeDisabled() // a 100 o comentário é opcional
    fireEvent.click(confirmar)

    await waitFor(() => expect(api.create).toHaveBeenCalledTimes(1))
    expect(api.create.mock.calls[0][1]).toMatchObject({ progress: 100, lock_version: 0 })
    expect(api.create.mock.calls[0][1].comment).toBeUndefined()
  })

  it('45 → 60 sem comentário: confirmar BLOQUEADO e nada é enviado', () => {
    const client = newClient()
    seed(client, task({ progress: 45 }))
    renderControls(client)

    fireEvent.click(screen.getByLabelText('+10%'))
    fireEvent.change(screen.getByLabelText('Progresso alvo (%)'), { target: { value: '60' } })

    expect(screen.getByRole('button', { name: 'Registrar' })).toBeDisabled()
    // três espaços não habilitam (mesmo btrim do banco)
    fireEvent.change(screen.getByLabelText(/Comentário/), { target: { value: '   ' } })
    expect(screen.getByRole('button', { name: 'Registrar' })).toBeDisabled()
    expect(api.create).not.toHaveBeenCalled()
  })
})

describe('leitura viva do progresso (D-UI)', () => {
  it('dois +10 sucessivos somam +20 porque cada passo lê o cache atual', () => {
    const client = newClient()
    seed(client, task({ progress: 45 }))
    const wrapper = ({ children }: { children: ReactNode }) => (
      <QueryClientProvider client={client}>{children}</QueryClientProvider>
    )
    const { result } = renderHook(() => useAdvanceDraft('r1', 't1'), { wrapper })

    act(() => result.current.step(10))
    expect(result.current.value).toBe(55)

    // simula o sucesso do primeiro avanço: cache invalidado/atualizado para 55
    act(() => {
      seed(client, task({ progress: 55, lock_version: 1 }))
      result.current.reset()
    })
    act(() => result.current.step(10))
    expect(result.current.value).toBe(65) // +20 no total, não +10 repetido
  })

  it('+10 em 95 abre em 100 (clamp)', () => {
    const client = newClient()
    seed(client, task({ progress: 95 }))
    const wrapper = ({ children }: { children: ReactNode }) => (
      <QueryClientProvider client={client}>{children}</QueryClientProvider>
    )
    const { result } = renderHook(() => useAdvanceDraft('r1', 't1'), { wrapper })
    act(() => result.current.step(10))
    expect(result.current.value).toBe(100)
  })
})

describe('arrastar e cancelar (§2.4 item 5)', () => {
  it('arrastar até 60 e cancelar devolve o slider a 45 sem nenhuma requisição', () => {
    const client = newClient()
    seed(client, task({ progress: 45 }))
    renderControls(client)

    const slider = screen.getByLabelText('Progresso da tarefa')
    fireEvent.change(slider, { target: { value: '60' } })
    expect((slider as HTMLInputElement).value).toBe('60')

    fireEvent.click(screen.getByRole('button', { name: 'Cancelar' }))
    expect((screen.getByLabelText('Progresso da tarefa') as HTMLInputElement).value).toBe('45')
    expect(api.create).not.toHaveBeenCalled()
  })
})

describe('conflito 409 (D-409)', () => {
  it('preserva o comentário, oferece recalcular e envia um uuid NOVO', async () => {
    const client = newClient()
    seed(client, task({ progress: 45, lock_version: 0 }))
    // primeiro envio → 409; segundo (após recalcular) → sucesso
    api.create
      .mockRejectedValueOnce({
        response: {
          status: 409,
          data: {
            error: 'conflito_de_versao',
            task: { id: 't1', progress: 70, status: 'Em Andamento', lock_version: 8 },
            latest_advance: { author_name_snapshot: 'Ana', to_progress: 70, recorded_at: '2026-01-01T00:00:00Z', comment: 'ok' },
          },
        },
      })
      .mockResolvedValueOnce({ advance: {}, task: task({ progress: 85 }), replay: false })
    renderControls(client)

    fireEvent.click(screen.getByLabelText('+10%'))
    fireEvent.change(screen.getByLabelText('Progresso alvo (%)'), { target: { value: '60' } })
    fireEvent.change(screen.getByLabelText(/Comentário/), { target: { value: 'faltou aterrar' } })
    fireEvent.click(screen.getByRole('button', { name: 'Registrar' }))

    // corpo do conflito aparece
    await screen.findByText('Alguém avançou esta tarefa enquanto você escrevia')
    const uuid1 = api.create.mock.calls[0][1].id

    fireEvent.click(screen.getByRole('button', { name: 'Recalcular a partir de 70%' }))

    // o comentário foi preservado
    const comentario = screen.getByLabelText(/Comentário/) as HTMLTextAreaElement
    expect(comentario.value).toBe('faltou aterrar')

    fireEvent.click(screen.getByRole('button', { name: 'Registrar' }))
    await waitFor(() => expect(api.create).toHaveBeenCalledTimes(2))
    const uuid2 = api.create.mock.calls[1][1].id
    expect(uuid2).not.toBe(uuid1) // outro fato → outro uuid
    expect(api.create.mock.calls[1][1]).toMatchObject({ lock_version: 8, progress: 85 })
  })
})

describe('somente-leitura para view (5.6)', () => {
  it('view não vê os botões e o slider é aria-disabled', () => {
    ROLE = 'view'
    const client = newClient()
    seed(client, task({ progress: 45 }))
    renderControls(client)

    expect(screen.queryByLabelText('+10%')).toBeNull()
    expect(screen.queryByLabelText('−10%')).toBeNull()
    const slider = screen.getByLabelText('Progresso da tarefa')
    expect(slider).toHaveAttribute('aria-disabled', 'true')
  })
})
