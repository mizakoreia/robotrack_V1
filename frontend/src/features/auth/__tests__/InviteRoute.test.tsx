import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { render, screen, waitFor, cleanup } from '@testing-library/react'
import { MemoryRouter, Route, Routes } from 'react-router-dom'

// workspace-invitations 5.1/5.2 — a rota do convidado.
//
// As falhas a caçar: o token ficar na barra de endereço (ele é credencial, e
// URL vaza por histórico, referrer e captura de tela); o convidado fazer login
// sem saber para onde está sendo convidado; e — a que trava o usuário — um
// aceite falho continuar sendo reemitido a cada navegação porque o token não foi
// removido do storage.

const { previewMock, acceptMock, toastMock, navigateMock } = vi.hoisted(() => ({
  previewMock: vi.fn(),
  acceptMock: vi.fn(),
  toastMock: { warning: vi.fn(), error: vi.fn(), success: vi.fn(), info: vi.fn() },
  navigateMock: vi.fn(),
}))

vi.mock('../../../lib/api/endpoints', () => ({
  authApi: { logout: vi.fn() },
  invitationsApi: { preview: previewMock, accept: acceptMock },
}))

vi.mock('sonner', () => ({ toast: toastMock }))

vi.mock('react-router-dom', async () => {
  const real = await vi.importActual<typeof import('react-router-dom')>('react-router-dom')
  return { ...real, useNavigate: () => navigateMock }
})

import { InviteRoute } from '../InviteRoute'
import { inviteStore } from '../../../lib/auth/invite'
import { useAuthStore } from '../../../store/authStore'

const TOKEN = 'rt_inv_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmno'

function renderRota() {
  return render(
    <MemoryRouter initialEntries={[`/convite/${TOKEN}`]}>
      <Routes>
        <Route path="/convite/:token" element={<InviteRoute />} />
      </Routes>
    </MemoryRouter>,
  )
}

describe('InviteRoute', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    inviteStore.clear()
    useAuthStore.getState().clearSession()
    sessionStorage.clear()
    window.history.replaceState(null, '', '/')
    previewMock.mockResolvedValue({
      workspace_name: 'Linha 3',
      role: 'view',
      email_masked: 'j***@fabrica.com',
      expires_at: '2026-07-28T10:00:00Z',
      status: 'pending',
    })
  })

  afterEach(cleanup)

  it('guarda o token e TIRA o token da URL (history.replaceState)', async () => {
    const replaceState = vi.spyOn(window.history, 'replaceState')
    renderRota()

    await waitFor(() => expect(inviteStore.read()).toBe(TOKEN))
    expect(replaceState).toHaveBeenCalled()
    const urlFinal = replaceState.mock.calls.at(-1)?.[2] as string
    expect(urlFinal).not.toContain(TOKEN)
    expect(window.location.href).not.toContain(TOKEN)
  })

  it('mostra a pré-visualização: workspace, papel e e-mail MASCARADO', async () => {
    renderRota()

    expect(await screen.findByText('Linha 3')).toBeInTheDocument()
    expect(screen.getByText(/permissão para visualizar/)).toBeInTheDocument()
    expect(screen.getByText(/j\*\*\*@fabrica\.com/)).toBeInTheDocument()
    // O e-mail completo NUNCA aparece — vazar o destinatário entrega um alvo de
    // phishing a quem interceptar o link.
    expect(screen.queryByText(/joao@fabrica\.com/)).toBeNull()
  })

  it('convite expirado é anunciado e não oferece o caminho de entrada', async () => {
    previewMock.mockResolvedValue({
      workspace_name: 'Linha 3',
      role: 'edit',
      email_masked: 'j***@fabrica.com',
      expires_at: '2026-07-01T10:00:00Z',
      status: 'expired',
    })
    renderRota()

    expect(await screen.findByText(/Este convite expirou/)).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Entrar para aceitar' })).toBeNull()
  })

  it('token inexistente explica em vez de mandar o usuário a lugar nenhum', async () => {
    previewMock.mockRejectedValue({ response: { status: 404 } })
    renderRota()

    expect(await screen.findByText(/Convite não encontrado/)).toBeInTheDocument()
    expect(toastMock.error).toHaveBeenCalledWith(expect.stringMatching(/não encontrado/i))
  })

  it('com sessão ativa, aceita direto e não passa pela tela de login', async () => {
    useAuthStore.getState().setSession('token-x', { id: 'u1' } as never, { remember: false })
    acceptMock.mockResolvedValue({ workspace_id: 'ws-a', role: 'view' })

    renderRota()

    await waitFor(() => expect(acceptMock).toHaveBeenCalledWith(TOKEN))
    expect(previewMock).not.toHaveBeenCalled()
    await waitFor(() => expect(navigateMock).toHaveBeenCalledWith('/dashboard'))
    // Limpo em QUALQUER desfecho: uma navegação seguinte não reemite o aceite.
    expect(inviteStore.read()).toBeNull()
  })

  it('aceite com e-mail divergente limpa o token e oferece trocar de conta', async () => {
    useAuthStore.getState().setSession('token-x', { id: 'u1' } as never, { remember: false })
    acceptMock.mockRejectedValue({
      response: { status: 403, data: { error: 'invitation_email_mismatch' } },
    })

    renderRota()

    await waitFor(() => expect(toastMock.warning).toHaveBeenCalled())
    const [mensagem, opcoes] = toastMock.warning.mock.calls.at(-1) as [string, { duration: number; action: { label: string } }]
    expect(mensagem).toMatch(/j\*\*\*@fabrica\.com/)
    expect(opcoes.duration).toBe(Infinity)
    expect(opcoes.action.label).toMatch(/outra conta/i)
    expect(inviteStore.read()).toBeNull()
  })
})
