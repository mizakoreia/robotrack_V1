import type { ReactNode } from 'react'
import { describe, expect, it, vi, beforeEach, afterEach } from 'vitest'
import { render, screen, within, act } from '@testing-library/react'
import { MemoryRouter, Routes, Route, Link } from 'react-router-dom'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { AppShell } from '../AppShell'
import { workspacesApi } from '@/lib/api/endpoints'
import { useAuthStore } from '@/store/authStore'
import { useWorkspaceStore } from '@/store/workspaceStore'
import { inviteText } from '@/lib/i18n/invitations'

// app-shell-navigation 4.6 (§3.10) — os testes da casca: 3 destinos, ausência de
// faixa lateral (ativo é preenchimento, não borda), `aria-current` no corrente,
// scroll ao topo na navegação, e topbar a 375px. Falha no instante em que alguém
// promover "Configurações" a quarto item da sidebar ou trocar o realce por barra.

function seedStores() {
  useAuthStore.setState({ user: { id: 'u1', name: 'Ana Lima', email: 'ana@ex.com' } })
  useWorkspaceStore.setState({
    workspaces: [{ id: 'betim', name: 'Betim', role: 'owner' }],
    currentWorkspaceId: 'betim',
    currentRoleLabel: 'owner',
  })
}

// QueryClient próprio: a topbar monta o WorkspaceContext, que carrega o índice.
function Providers({ children, initial }: { children: ReactNode; initial: string }) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false, gcTime: 0 } } })
  return (
    <QueryClientProvider client={client}>
      <MemoryRouter initialEntries={[initial]}>{children}</MemoryRouter>
    </QueryClientProvider>
  )
}

function Shell({ initial = '/' }: { initial?: string }) {
  return (
    <Providers initial={initial}>
      <Routes>
        <Route element={<AppShell />}>
          <Route path="/" element={<div>conteúdo visão geral</div>} />
          <Route path="/minhas-tarefas" element={<div>conteúdo minhas tarefas</div>} />
          <Route path="/relatorio" element={<div>conteúdo relatório</div>} />
        </Route>
      </Routes>
    </Providers>
  )
}

beforeEach(() => {
  document.getElementById('rt-overlays')?.remove()
  // jsdom não implementa Element.scrollTo — a casca chama em `.main` a cada nav.
  Element.prototype.scrollTo = vi.fn() as unknown as Element['scrollTo']
  // o índice de workspaces é carregado pelo WorkspaceContext; devolve o corrente.
  vi.spyOn(workspacesApi, 'list').mockResolvedValue([{ id: 'betim', name: 'Betim', role: 'owner' }])
  seedStores()
})
afterEach(() => {
  vi.restoreAllMocks()
})

describe('AppShell (§3.10, D-F)', () => {
  it('a sidebar tem EXATAMENTE três destinos', () => {
    render(<Shell />)
    const nav = screen.getByRole('navigation', { name: 'Navegação principal' })
    expect(within(nav).getAllByRole('link')).toHaveLength(3)
  })

  it('o destino corrente carrega aria-current="page"; os outros, não', () => {
    render(<Shell initial="/minhas-tarefas" />)
    const nav = screen.getByRole('navigation', { name: 'Navegação principal' })
    const current = within(nav).getByRole('link', { current: 'page' })
    expect(current).toHaveTextContent('Minhas Tarefas')
    // exatamente um destino é o corrente
    expect(within(nav).getAllByRole('link', { current: 'page' })).toHaveLength(1)
  })

  it('"Visão Geral" fica ativo em toda a subárvore da hierarquia', () => {
    render(
      <Providers initial="/projeto/8f2a/celula/1c9b">
        <Routes>
          <Route element={<AppShell />}>
            <Route path="/projeto/:pid/celula/:cid" element={<div>subárvore</div>} />
          </Route>
        </Routes>
      </Providers>,
    )
    const nav = screen.getByRole('navigation', { name: 'Navegação principal' })
    expect(within(nav).getByRole('link', { current: 'page' })).toHaveTextContent('Visão Geral')
  })

  it('o realce ativo é preenchimento tintado, NUNCA faixa lateral (sem border-left)', () => {
    render(<Shell initial="/relatorio" />)
    const nav = screen.getByRole('navigation', { name: 'Navegação principal' })
    const active = within(nav).getByRole('link', { current: 'page' })
    // preenchimento presente, borda lateral ausente — o teste que trava a regra
    expect(active.className).toMatch(/bg-accent\//)
    expect(active.className).not.toMatch(/border-l/)
    expect(active.className).not.toMatch(/before:/)
  })

  it('nenhum item de configuração aparece na sidebar (papel Dono)', () => {
    render(<Shell />)
    const nav = screen.getByRole('navigation', { name: 'Navegação principal' })
    expect(within(nav).queryByText(/Configuraç/i)).toBeNull()
  })

  it('rola o CONTEÚDO ao topo a cada navegação (o body não rola — só `.main`)', () => {
    const scrollTo = vi.fn()
    Element.prototype.scrollTo = scrollTo as unknown as Element['scrollTo']

    render(
      <Providers initial="/">
        <Routes>
          <Route element={<AppShell />}>
            <Route path="/" element={<Link to="/relatorio">ir ao relatório</Link>} />
            <Route path="/relatorio" element={<div>conteúdo relatório</div>} />
          </Route>
        </Routes>
      </Providers>,
    )
    scrollTo.mockClear()
    act(() => {
      screen.getByRole('link', { name: 'ir ao relatório' }).click()
    })
    expect(scrollTo).toHaveBeenCalledWith(expect.objectContaining({ top: 0 }))
  })

  it('a topbar renderiza a 375px com o gatilho da gaveta', () => {
    window.innerWidth = 375
    render(<Shell />)
    expect(screen.getByRole('button', { name: 'Abrir menu' })).toBeInTheDocument()
    // As ações de conta NÃO moram mais num segundo menu na topbar: o card de
    // usuário da sidebar é o menu único de conta (ver o teste abaixo).
    expect(screen.queryByRole('button', { name: 'Conta' })).toBeNull()
  })

  // O menu de conta consolidado: tema e sair moraram na topbar; agora estão no
  // card de usuário (canto inferior esquerdo), junto dos destinos de gestão.
  it('o card de usuário abre o menu de conta com tema e sair', () => {
    render(<Shell />)
    const card = screen.getByRole('button', { name: /^Conta:/ })
    act(() => card.click())
    const menu = screen.getByRole('menu', { name: 'Conta' })
    for (const label of [
      'Configurações do workspace',
      'Equipe e convites',
      inviteText.joinByCodeMenu,
      'Alternar tema',
      'Sair',
    ]) {
      expect(within(menu).getByRole('menuitem', { name: label })).toBeInTheDocument()
    }
  })

  // join-workspace-by-code — a porta para entrar noutro workspace por código vive
  // no menu da conta, SEMPRE acessível: aqui o usuário tem um único workspace
  // (seedStores), então o seletor de workspace nem existe — e a porta continua lá.
  it('o menu da conta oferece "Entrar em outro workspace com código" mesmo com um só workspace', () => {
    render(<Shell />)
    act(() => screen.getByRole('button', { name: /^Conta:/ }).click())
    const menu = screen.getByRole('menu', { name: 'Conta' })
    expect(within(menu).getByRole('menuitem', { name: inviteText.joinByCodeMenu })).toBeInTheDocument()
  })

  it('escolher o item abre o diálogo de entrada por código (?codigo=1)', () => {
    render(<Shell />)
    act(() => screen.getByRole('button', { name: /^Conta:/ }).click())
    act(() => {
      screen.getByRole('menuitem', { name: inviteText.joinByCodeMenu }).click()
    })
    expect(screen.getByRole('dialog', { name: inviteText.joinByCodeTitle })).toBeInTheDocument()
    // e o e-mail da sessão aparece como contexto (identidade do aceite)
    expect(screen.getByText(inviteText.joinByCodeAs('ana@ex.com'))).toBeInTheDocument()
  })

  it('o card de usuário usa o e-mail como fallback quando o nome é vazio', () => {
    useAuthStore.setState({ user: { id: 'u2', name: '  ', email: 'sem-nome@ex.com' } })
    render(<Shell />)
    // o e-mail aparece UMA vez (sem nome não repete o e-mail em cima e embaixo)
    expect(screen.getAllByText('sem-nome@ex.com')).toHaveLength(1)
  })
})
