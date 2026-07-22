import { describe, expect, it, vi, beforeEach, afterEach } from 'vitest'
import { render, screen, waitFor, fireEvent } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { MemoryRouter, Routes, Route } from 'react-router-dom'
import { OverviewPage } from '@/app/pages/OverviewPage'
import { ProjectPage } from '@/app/pages/ProjectPage'
import { CellPage } from '@/app/pages/CellPage'
import { overviewApi } from '@/lib/api/endpoints'
import { useWorkspaceStore } from '@/store/workspaceStore'

// hierarchy-screens 5.6 (§3.2–§3.4) — o caminho Visão Geral → Projeto → Célula e o
// voltar. Voltar da CÉLULA retorna ao PROJETO de origem, não à Visão Geral.
const W = (value: number) => ({ value, metric: 'weighted' as const, label: 'Progresso ponderado' })
const RAW = { completed: 1, total: 4, percent: 25, metric: 'raw_count' as const, label: 'x' }

function mountApp() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false, gcTime: 0 } } })
  return render(
    <QueryClientProvider client={client}>
      <MemoryRouter initialEntries={['/']}>
        <Routes>
          <Route path="/" element={<OverviewPage />} />
          <Route path="/projeto/:id" element={<ProjectPage />} />
          <Route path="/celula/:id" element={<CellPage />} />
        </Routes>
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
  vi.spyOn(overviewApi, 'workspace').mockResolvedValue({
    counts: { active_projects: 1, analyzed_robots: 1 },
    raw_completion: RAW,
    projects: [{ id: 'p1', name: 'Linha 300', cells_count: 1, weighted_progress: W(40) }],
  })
  vi.spyOn(overviewApi, 'project').mockResolvedValue({
    id: 'p1', name: 'Linha 300',
    counts: { configured_cells: 1, analyzed_robots: 1 },
    raw_completion: RAW,
    cells: [{ id: 'c1', name: 'Célula 01', weighted_progress: W(40), robots_count: 1, lock_version: 0 }],
  })
  vi.spyOn(overviewApi, 'cell').mockResolvedValue({
    id: 'c1', name: 'Célula 01', project_id: 'p1',
    counts: { configured_robots: 1 },
    raw_completion: RAW,
    robots: [{ id: 'r1', name: 'R01', application: 'Solda Ponto', weighted_progress: W(40), tasks_count: 4 }],
  })
})
afterEach(() => vi.restoreAllMocks())

describe('navegação da hierarquia (5.6)', () => {
  it('Visão Geral → Projeto → Célula, e voltar da célula retorna ao PROJETO', async () => {
    mountApp()

    // Visão Geral: o card do projeto
    expect(await screen.findByText('Linha 300')).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: 'Acessar' }))

    // Projeto: título + card da célula
    await waitFor(() => expect(screen.getByRole('heading', { name: 'Linha 300' })).toBeInTheDocument())
    expect(await screen.findByText('Célula 01')).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: 'Acessar' }))

    // Célula: título + card do robô
    await waitFor(() => expect(screen.getByRole('heading', { name: 'Célula 01' })).toBeInTheDocument())
    expect(await screen.findByText('R01')).toBeInTheDocument()

    // Voltar: retorna ao PROJETO de origem (não à Visão Geral)
    fireEvent.click(screen.getByRole('button', { name: 'Voltar ao projeto' }))
    await waitFor(() => expect(screen.getByRole('heading', { name: 'Linha 300' })).toBeInTheDocument())
    // prova de que NÃO caiu na Visão Geral: o hub de projeto ("Células configuradas") está lá
    expect(screen.getByText('Células configuradas')).toBeInTheDocument()
  })
})
