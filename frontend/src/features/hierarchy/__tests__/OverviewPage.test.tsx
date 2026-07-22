import { describe, expect, it, vi, beforeEach, afterEach } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { MemoryRouter } from 'react-router-dom'
import { OverviewPage } from '@/app/pages/OverviewPage'
import { overviewApi, type WorkspaceOverviewDTO } from '@/lib/api/endpoints'
import { useWorkspaceStore } from '@/store/workspaceStore'

// hierarchy-screens 4.6 (D15) — o teste sobre a fixture DIVERGENTE: o hub mostra a
// contagem crua ("1/4", "25% de progresso físico global") E o anel mostra o
// ponderado (40%, aria "Progresso ponderado: 40%"). Se alguém unificar as métricas,
// os dois viram o mesmo número e este teste quebra.
const DIVERGENT: WorkspaceOverviewDTO = {
  counts: { active_projects: 1, analyzed_robots: 1 },
  raw_completion: { completed: 1, total: 4, percent: 25, metric: 'raw_count', label: 'Progresso físico (tarefas concluídas)' },
  projects: [
    { id: 'p1', name: 'Linha 300', cells_count: 4, weighted_progress: { value: 40, metric: 'weighted', label: 'Progresso ponderado' } },
  ],
}

function renderPage() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false, gcTime: 0 } } })
  return render(
    <QueryClientProvider client={client}>
      <MemoryRouter>
        <OverviewPage />
      </MemoryRouter>
    </QueryClientProvider>,
  )
}

beforeEach(() => {
  document.getElementById('rt-overlays')?.remove()
  useWorkspaceStore.setState({
    workspaces: [{ id: 'betim', name: 'Betim', role: 'owner' }],
    currentWorkspaceId: 'betim',
    currentRoleLabel: 'owner',
  })
})
afterEach(() => vi.restoreAllMocks())

describe('OverviewPage — as duas métricas (D15)', () => {
  it('hub mostra a contagem crua e o anel o ponderado — divergentes', async () => {
    vi.spyOn(overviewApi, 'workspace').mockResolvedValue(DIVERGENT)
    renderPage()

    // hub (contagem crua §3.2)
    expect(await screen.findByText('1/4')).toBeInTheDocument()
    expect(screen.getByText('25% de progresso físico global')).toBeInTheDocument()

    // anel (ponderado §2.1) — o nó acessível carrega o rótulo da métrica
    expect(screen.getByLabelText('Progresso ponderado: 40%')).toBeInTheDocument()

    // a prova do D15: os dois números NÃO são iguais
    expect(screen.queryByText('40% de progresso físico global')).toBeNull()
  })

  it('o card mostra o badge de contagem de células e o rodapé Acessar', async () => {
    vi.spyOn(overviewApi, 'workspace').mockResolvedValue(DIVERGENT)
    renderPage()
    expect(await screen.findByText('4 células')).toBeInTheDocument()
    expect(screen.getByText('Acessar')).toBeInTheDocument()
    expect(screen.getByText('Linha 300')).toBeInTheDocument()
  })
})

describe('OverviewPage — estados', () => {
  const EMPTY: WorkspaceOverviewDTO = {
    counts: { active_projects: 0, analyzed_robots: 0 },
    raw_completion: { completed: 0, total: 0, percent: 0, metric: 'raw_count', label: 'x' },
    projects: [],
  }

  it('vazio + papel owner: mostra CTA "Novo Projeto"', async () => {
    vi.spyOn(overviewApi, 'workspace').mockResolvedValue(EMPTY)
    renderPage()
    expect(await screen.findByRole('button', { name: /Novo Projeto/ })).toBeInTheDocument()
  })

  it('vazio + papel view: NÃO mostra CTA de criação', async () => {
    useWorkspaceStore.setState({ currentRoleLabel: 'view' })
    vi.spyOn(overviewApi, 'workspace').mockResolvedValue(EMPTY)
    renderPage()
    await waitFor(() => expect(overviewApi.workspace).toHaveBeenCalled())
    expect(screen.queryByRole('button', { name: /Novo Projeto/ })).toBeNull()
  })

  it('erro: mostra "Tentar novamente", não o estado vazio', async () => {
    vi.spyOn(overviewApi, 'workspace').mockRejectedValue(new Error('500'))
    renderPage()
    expect(await screen.findByRole('button', { name: 'Tentar novamente' })).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: /Novo Projeto/ })).toBeNull()
  })
})
