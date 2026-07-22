import { describe, expect, it, vi, beforeEach, afterEach } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { MemoryRouter } from 'react-router-dom'
import { WorkspaceContext } from '../WorkspaceContext'
import { workspacesApi } from '@/lib/api/endpoints'
import { useWorkspaceStore } from '@/store/workspaceStore'
import * as revoked from '@/lib/workspace/accessRevoked'

// app-shell-navigation 5.9 (§3.10, D-G) — o contexto: seletor ausente com 1
// workspace (texto estático, não select desabilitado), presente com 2; badge para
// cada um dos 3 papéis; e a degradação do índice (vazio e erro de rede) que mantém
// a casca sem seletor e sem badge, com nova tentativa.

function renderCtx() {
  // QueryClient PRÓPRIO por teste (retry off): isola o índice entre exemplos.
  const client = new QueryClient({ defaultOptions: { queries: { retry: false, gcTime: 0 } } })
  return render(
    <QueryClientProvider client={client}>
      <MemoryRouter>
        <WorkspaceContext />
      </MemoryRouter>
    </QueryClientProvider>,
  )
}

let listSpy: ReturnType<typeof vi.spyOn>

beforeEach(() => {
  document.getElementById('rt-overlays')?.remove()
  useWorkspaceStore.setState({ workspaces: [], currentWorkspaceId: null, currentRoleLabel: null })
  // handleAccessRevoked navega/toasta; neutralizado para os testes de índice.
  vi.spyOn(revoked, 'handleAccessRevoked').mockImplementation(() => {})
  listSpy = vi.spyOn(workspacesApi, 'list')
})
afterEach(() => {
  vi.restoreAllMocks()
})

describe('WorkspaceContext (§3.10, D-G)', () => {
  it('com 1 workspace: nome como texto estático, SEM seletor (não é select desabilitado)', async () => {
    useWorkspaceStore.setState({
      workspaces: [{ id: 'betim', name: 'Betim', role: 'owner' }],
      currentWorkspaceId: 'betim',
      currentRoleLabel: 'owner',
    })
    listSpy.mockResolvedValue([{ id: 'betim', name: 'Betim', role: 'owner' }])
    renderCtx()

    expect(await screen.findByText('Betim')).toBeInTheDocument()
    // nenhum controle: sem botão de seletor, sem `disabled`, sem `aria-disabled`
    expect(screen.queryByRole('button')).toBeNull()
    const name = screen.getByText('Betim')
    expect(name.tagName).toBe('SPAN')
    expect(name).toHaveAttribute('tabindex', '-1')
  })

  it('com 2 workspaces: seletor presente (botão com aria-haspopup)', async () => {
    useWorkspaceStore.setState({
      workspaces: [
        { id: 'betim', name: 'Betim', role: 'owner' },
        { id: 'camacari', name: 'Camaçari', role: 'edit' },
      ],
      currentWorkspaceId: 'betim',
      currentRoleLabel: 'owner',
    })
    listSpy.mockResolvedValue([
      { id: 'betim', name: 'Betim', role: 'owner' },
      { id: 'camacari', name: 'Camaçari', role: 'edit' },
    ])
    renderCtx()

    const trigger = await screen.findByRole('button')
    expect(trigger).toHaveAttribute('aria-haspopup', 'menu')
    expect(trigger).toHaveTextContent('Betim')
  })

  it.each([
    ['owner', 'Dono'],
    ['edit', 'Editor'],
    ['view', 'Somente leitura'],
  ])('badge do papel %s exibe "%s"', async (role, label) => {
    useWorkspaceStore.setState({
      workspaces: [{ id: 'w', name: 'W', role }],
      currentWorkspaceId: 'w',
      currentRoleLabel: role,
    })
    listSpy.mockResolvedValue([{ id: 'w', name: 'W', role }])
    renderCtx()
    expect(await screen.findByText(label)).toBeInTheDocument()
  })

  it('papel ausente cai para "Somente leitura"', async () => {
    useWorkspaceStore.setState({
      workspaces: [{ id: 'w', name: 'W', role: 'owner' }],
      currentWorkspaceId: 'w',
      currentRoleLabel: null, // papel não resolvido
    })
    listSpy.mockResolvedValue([{ id: 'w', name: 'W', role: 'owner' }])
    renderCtx()
    // com role=null, o RoleBadge cai para o rótulo de somente leitura
    expect(await screen.findByText('Somente leitura')).toBeInTheDocument()
  })

  it('degradação — índice VAZIO mantém a casca sem seletor e sem badge', async () => {
    listSpy.mockResolvedValue([]) // índice vazio
    renderCtx()
    await waitFor(() => expect(listSpy).toHaveBeenCalled())
    // sem seletor, sem badge de papel
    expect(screen.queryByRole('button')).toBeNull()
    expect(screen.queryByText(/Dono|Editor|Somente leitura/)).toBeNull()
  })

  it('degradação — ERRO de rede mantém a casca navegável com ação de nova tentativa', async () => {
    listSpy.mockRejectedValue(new Error('rede caiu'))
    renderCtx()
    // a ação de recarregar aparece; nenhum badge é exibido
    expect(await screen.findByRole('button', { name: 'Recarregar' })).toBeInTheDocument()
    expect(screen.queryByText(/Dono|Editor|Somente leitura/)).toBeNull()
  })
})
