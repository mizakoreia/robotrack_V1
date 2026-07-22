import { describe, expect, it, vi, beforeEach, afterEach } from 'vitest'
import { render, screen, waitFor, within } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { MemoryRouter } from 'react-router-dom'
import { MyTasksPage } from '@/app/pages/MyTasksPage'
import { myTasksApi, type MyTaskRowDTO } from '@/lib/api/endpoints'
import { useWorkspaceStore } from '@/store/workspaceStore'

// my-tasks-view 6.7 (§3.6, D-MTV-2/8/9) — os três estados distintos (o 409 NUNCA
// colapsa no vazio), a linha como deep-link navegável, a ausência de controles de
// mutação, e a partição por workspace (trocar de workspace não mostra linhas do
// anterior).

// o canal ao vivo (useChannel) é no-op nos testes — sem ActionCable no jsdom.
vi.mock('@/hooks/useCable', () => ({ useCable: () => null, useChannel: () => null }))

function row(over: Partial<MyTaskRowDTO> = {}): MyTaskRowDTO {
  return {
    id: 't1', description: 'Fixar base', status: 'Em Andamento', progress: 45,
    category: 'A. Hardware', robot_id: 'r1', robot_name: 'R01',
    cell_id: 'c1', cell_name: 'Célula 01', project_id: 'p1', project_name: 'Linha 300', ...over,
  }
}

function renderPage() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false, retryDelay: 0, gcTime: 0 } } })
  render(
    <QueryClientProvider client={client}>
      <MemoryRouter>
        <MyTasksPage />
      </MemoryRouter>
    </QueryClientProvider>,
  )
  return client
}

beforeEach(() => {
  useWorkspaceStore.setState({
    workspaces: [{ id: 'betim', name: 'Betim', role: 'owner' }],
    currentWorkspaceId: 'betim', currentRoleLabel: 'owner',
  })
})
afterEach(() => vi.restoreAllMocks())

describe('estados (D-MTV-8)', () => {
  it('vazio legítimo: título do vazio, não o de identidade', async () => {
    vi.spyOn(myTasksApi, 'list').mockResolvedValue([])
    renderPage()
    expect(await screen.findByText('Nenhuma tarefa aberta atribuída a você')).toBeInTheDocument()
    expect(screen.queryByText('Não foi possível identificar seu cadastro neste workspace.')).toBeNull()
  })

  it('409 person_missing: estado de IDENTIDADE, jamais o vazio (falha silenciosa morta)', async () => {
    vi.spyOn(myTasksApi, 'list').mockRejectedValue({ response: { status: 409, data: { error: 'person_missing' } } })
    renderPage()
    expect(await screen.findByText('Não foi possível identificar seu cadastro neste workspace.')).toBeInTheDocument()
    expect(screen.queryByText('Nenhuma tarefa aberta atribuída a você')).toBeNull()
    expect(screen.getByRole('alert')).toBeInTheDocument()
  })

  it('erro de rede (500): estado de erro, distinto do 409 e do vazio', async () => {
    vi.spyOn(myTasksApi, 'list').mockRejectedValue({ response: { status: 500 } })
    renderPage()
    expect(await screen.findByText('Não foi possível carregar suas tarefas.')).toBeInTheDocument()
    expect(screen.queryByText('Não foi possível identificar seu cadastro neste workspace.')).toBeNull()
  })
})

describe('lista', () => {
  it('a linha é um link deep-link para a tarefa no robô (navegável por teclado)', async () => {
    vi.spyOn(myTasksApi, 'list').mockResolvedValue([row({ id: 'tX', robot_id: 'rX', description: 'Alinhar' })])
    renderPage()
    const link = await screen.findByRole('link', { name: 'Abrir Alinhar no robô R01' })
    expect(link).toHaveAttribute('href', '/robo/rX?task=tX') // query string (D-MTV-9), abre em nova aba
  })

  it('LEITURA PURA: sem seletor de status nem controles de mutação', async () => {
    vi.spyOn(myTasksApi, 'list').mockResolvedValue([row()])
    renderPage()
    await screen.findByText('Fixar base')
    expect(screen.queryByRole('combobox')).toBeNull() // status é Badge, não <select>
    expect(screen.queryByLabelText('+10%')).toBeNull()
    expect(screen.queryByRole('slider')).toBeNull()
    // o status aparece como texto de badge
    expect(screen.getByText('Em Andamento')).toBeInTheDocument()
  })
})

describe('partição por workspace (D2/D9)', () => {
  it('trocar de workspace não mostra as linhas do anterior', async () => {
    vi.spyOn(myTasksApi, 'list').mockImplementation(() => {
      const ws = useWorkspaceStore.getState().currentWorkspaceId
      return Promise.resolve(ws === 'betim' ? [row({ id: 'A', description: 'Tarefa de Betim' })] : [row({ id: 'B', description: 'Tarefa de Contagem' })])
    })
    renderPage()
    expect(await screen.findByText('Tarefa de Betim')).toBeInTheDocument()

    // troca de workspace (a chave qk.myTasks(wsId) parte por workspace)
    useWorkspaceStore.setState({ currentWorkspaceId: 'contagem', currentRoleLabel: 'owner' })

    await waitFor(() => expect(screen.getByText('Tarefa de Contagem')).toBeInTheDocument())
    expect(screen.queryByText('Tarefa de Betim')).toBeNull()
  })
})
