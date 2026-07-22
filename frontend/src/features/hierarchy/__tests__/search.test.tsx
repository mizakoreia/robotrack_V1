import { describe, expect, it, vi, beforeEach, afterEach } from 'vitest'
import { render, screen, waitFor, fireEvent } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { MemoryRouter } from 'react-router-dom'
import { OverviewPage } from '@/app/pages/OverviewPage'
import { overviewApi, type SearchResponse } from '@/lib/api/endpoints'
import { useWorkspaceStore } from '@/store/workspaceStore'

// hierarchy-screens 6.5 (§3.7) — 'sol' acha célula e robô (não a tarefa); 'xyz' vazio
// nomeando o termo; limpar restaura hub+grade. E Enter faz UMA busca (não duas).
const W = (v: number) => ({ value: v, metric: 'weighted' as const, label: 'Progresso ponderado' })

function respond(q: string): SearchResponse {
  if (q === 'sol') {
    return {
      count: 2,
      results: [
        { type: 'cell', id: 'c1', name: 'Solda 01', path_label: 'Célula · em Linha 300', route: '/celula/c1' },
        { type: 'robot', id: 'r2', name: 'R02 - Solda', path_label: 'Robô · em Solda 01 · Linha 300', route: '/robo/r2' },
      ],
    }
  }
  return { count: 0, results: [] }
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

let searchSpy: ReturnType<typeof vi.spyOn>

beforeEach(() => {
  document.getElementById('rt-overlays')?.remove()
  useWorkspaceStore.setState({
    workspaces: [{ id: 'betim', name: 'Betim', role: 'owner' }],
    currentWorkspaceId: 'betim',
    currentRoleLabel: 'owner',
  })
  vi.spyOn(overviewApi, 'workspace').mockResolvedValue({
    counts: { active_projects: 1, analyzed_robots: 1 },
    raw_completion: { completed: 1, total: 4, percent: 25, metric: 'raw_count', label: 'x' },
    projects: [{ id: 'p1', name: 'Linha 300', cells_count: 1, weighted_progress: W(40) }],
  })
  searchSpy = vi.spyOn(overviewApi, 'search').mockImplementation((q: string) => Promise.resolve(respond(q)))
})
afterEach(() => vi.restoreAllMocks())

function submitSearch(term: string) {
  fireEvent.change(screen.getByRole('searchbox'), { target: { value: term } })
  fireEvent.click(screen.getByRole('button', { name: 'Buscar' })) // flush + submit
}

describe('busca na Visão Geral (6.5)', () => {
  it('"sol" acha célula e robô, não a tarefa; limpar restaura o hub', async () => {
    renderPage()
    expect(await screen.findByText('1/4')).toBeInTheDocument() // hub visível antes

    submitSearch('sol')

    expect(await screen.findByText('Solda 01')).toBeInTheDocument()
    expect(screen.getByText('R02 - Solda')).toBeInTheDocument()
    expect(screen.queryByText('Solda MIG')).toBeNull() // tarefa fora do escopo
    expect(screen.getByText('2 resultados')).toBeInTheDocument()
    // hub substituído durante a busca
    expect(screen.queryByText('1/4')).toBeNull()

    fireEvent.click(screen.getByRole('button', { name: 'Limpar busca' }))
    expect(await screen.findByText('1/4')).toBeInTheDocument() // hub de volta
  })

  it('"xyz" mostra o vazio NOMEANDO o termo', async () => {
    renderPage()
    await screen.findByText('1/4')
    submitSearch('xyz')
    expect(await screen.findByText(/Nenhum resultado para/)).toBeInTheDocument()
    expect(screen.getByText('"xyz"')).toBeInTheDocument()
  })

  it('Enter logo após digitar executa UMA busca, não duas', async () => {
    renderPage()
    await screen.findByText('1/4')
    submitSearch('sol')
    await screen.findByText('Solda 01')
    // só o termo 'sol' foi buscado uma vez (o timer do debounce grava o mesmo termo)
    await waitFor(() => expect(searchSpy).toHaveBeenCalledWith('sol'))
    expect(searchSpy.mock.calls.filter((c) => c[0] === 'sol')).toHaveLength(1)
  })
})
