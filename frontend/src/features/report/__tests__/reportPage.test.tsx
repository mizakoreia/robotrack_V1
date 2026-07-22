import { describe, expect, it, vi, beforeEach, afterEach } from 'vitest'
import { render, screen, fireEvent } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { MemoryRouter } from 'react-router-dom'
import { ReportPage } from '@/app/pages/ReportPage'
import { reportApi, hierarchyApi } from '@/lib/api/endpoints'
import { useWorkspaceStore } from '@/store/workspaceStore'
import { reportFixture } from './report.test'

// commissioning-report 8.3 (§4.3) — a tela do Protocolo: seletor de escopo,
// carregando, erro acionável e offline explícito. O documento NUNCA aparece pela
// metade: no erro, nenhuma seção (nem cabeçalho nem carimbo) fica na tela.

function renderPage() {
  const client = new QueryClient({
    defaultOptions: { queries: { retry: false, retryDelay: 0, gcTime: 0 } },
  })
  render(
    <QueryClientProvider client={client}>
      <MemoryRouter>
        <ReportPage />
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
  vi.spyOn(hierarchyApi, 'listProjects').mockResolvedValue([])
})
afterEach(() => vi.restoreAllMocks())

describe('estados da tela (8.3, §4.3)', () => {
  it('sucesso: monta o documento inteiro (título, carimbo, seções)', async () => {
    vi.spyOn(reportApi, 'get').mockResolvedValue(reportFixture)
    renderPage()
    expect(await screen.findByRole('heading', { name: 'PROTOCOLO DE COMISSIONAMENTO' })).toBeInTheDocument()
    expect(screen.getByText('EM ANDAMENTO')).toBeInTheDocument()
    expect(screen.getByText('Conclusões')).toBeInTheDocument()
  })

  it('carregando: estado de status, sem nenhuma seção do documento', () => {
    vi.spyOn(reportApi, 'get').mockReturnValue(new Promise(() => {}))
    renderPage()
    expect(screen.getByRole('status')).toHaveTextContent('Montando o documento…')
    expect(screen.queryByText('PROTOCOLO DE COMISSIONAMENTO')).toBeNull()
  })

  it('500: erro acionável com retry — e NENHUMA seção parcial na tela', async () => {
    const spy = vi.spyOn(reportApi, 'get').mockRejectedValue({ response: { status: 500 } })
    renderPage()
    expect(await screen.findByText('Não foi possível emitir o documento')).toBeInTheDocument()
    expect(screen.queryByText('PROTOCOLO DE COMISSIONAMENTO')).toBeNull()
    expect(screen.queryByText('EM ANDAMENTO')).toBeNull()
    // retry aciona nova tentativa
    spy.mockResolvedValue(reportFixture)
    fireEvent.click(screen.getByRole('button', { name: 'Tentar novamente' }))
    expect(await screen.findByRole('heading', { name: 'PROTOCOLO DE COMISSIONAMENTO' })).toBeInTheDocument()
  })

  it('offline: informa que a emissão exige conexão (nada de cache parcial) e oferece retry', async () => {
    vi.spyOn(reportApi, 'get').mockResolvedValue(reportFixture)
    const onLine = vi.spyOn(window.navigator, 'onLine', 'get').mockReturnValue(false)
    renderPage()
    expect(await screen.findByText('Sem conexão')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Tentar novamente' })).toBeInTheDocument()
    expect(screen.queryByText('PROTOCOLO DE COMISSIONAMENTO')).toBeNull()
    onLine.mockRestore()
  })

  it('seletor de escopo: trocar para um projeto refaz a emissão com scope=project', async () => {
    vi.spyOn(hierarchyApi, 'listProjects').mockResolvedValue([
      { id: 'p1', name: 'Linha A' } as never,
    ])
    const spy = vi.spyOn(reportApi, 'get').mockResolvedValue(reportFixture)
    renderPage()
    await screen.findByRole('heading', { name: 'PROTOCOLO DE COMISSIONAMENTO' })
    expect(spy).toHaveBeenCalledWith('all', undefined)
    fireEvent.change(await screen.findByRole('combobox'), { target: { value: 'p1' } })
    expect(spy).toHaveBeenCalledWith('project', 'p1')
  })
})
