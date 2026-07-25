import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, fireEvent, waitFor, cleanup } from '@testing-library/react'

// invite-by-code §D — a seção "Tenho um código de convite" na tela de entrada.
// As falhas a caçar: formato inválido virar requisição (não deve); o par se perder
// no redirect do Google (tem de ser guardado ANTES do login); e o código não ser
// normalizado (o galpão digita torto).

const { captureCodeMock, markInviteEntryMock, consumeByCodeMock, toastMock, navigateMock } = vi.hoisted(() => ({
  captureCodeMock: vi.fn(() => true),
  markInviteEntryMock: vi.fn(),
  consumeByCodeMock: vi.fn(() => Promise.resolve()),
  toastMock: { warning: vi.fn(), error: vi.fn(), success: vi.fn(), info: vi.fn() },
  navigateMock: vi.fn(),
}))

vi.mock('../../../lib/api/endpoints', () => ({
  authApi: {
    googleRedirectUrl: () => 'https://accounts.google/x',
    login: vi.fn(),
    register: vi.fn(),
  },
}))

vi.mock('../../../lib/auth/session', () => ({
  handleInviteAfterAuth: vi.fn(() => Promise.resolve()),
  consumeInviteByCode: consumeByCodeMock,
}))

vi.mock('../../../lib/auth/invite', () => ({
  inviteStore: { captureCode: captureCodeMock },
}))

vi.mock('../../../lib/auth/oauthState', () => ({
  oauthState: { markInviteEntry: markInviteEntryMock, setRemember: vi.fn(), wasInviteEntry: vi.fn(), clearInviteEntry: vi.fn() },
}))

vi.mock('sonner', () => ({ toast: toastMock }))

vi.mock('react-router-dom', async () => {
  const real = await vi.importActual<typeof import('react-router-dom')>('react-router-dom')
  return { ...real, useNavigate: () => navigateMock }
})

import { AuthPage } from '../AuthPage'
import { useAuthStore } from '../../../store/authStore'
import { inviteText } from '../../../lib/i18n/invitations'

describe('AuthPage — seção de código de convite', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    useAuthStore.getState().clearSession()
    cleanup()
    render(<AuthPage />)
  })

  function preencher(email: string, code: string) {
    fireEvent.change(screen.getByLabelText(inviteText.codeEmailLabel), { target: { value: email } })
    fireEvent.change(screen.getByLabelText(inviteText.codeLabel), { target: { value: code } })
  }

  it('mostra a seção colapsável com o título', () => {
    expect(screen.getByText(inviteText.codeSectionTitle)).toBeInTheDocument()
  })

  it('máscara aplica XXXX-XXXX enquanto digita', () => {
    const campo = screen.getByLabelText(inviteText.codeLabel) as HTMLInputElement
    fireEvent.change(campo, { target: { value: '4k7p9qmx' } })
    expect(campo.value).toBe('4K7P-9QMX')
  })

  it('formato incompleto NÃO guarda o par nem chama a rede', () => {
    preencher('joao@fabrica.com', '4K7P-9QM') // 7 chars
    fireEvent.click(screen.getByRole('button', { name: inviteText.codeSubmitGuest }))

    expect(screen.getByText(inviteText.codeInvalidFormat)).toBeInTheDocument()
    expect(captureCodeMock).not.toHaveBeenCalled()
    expect(consumeByCodeMock).not.toHaveBeenCalled()
  })

  it('não autenticado: guarda o par NORMALIZADO e marca entrada por convite (sobrevive ao OAuth)', () => {
    preencher('joao@fabrica.com', '4k7p-9qmx')
    fireEvent.click(screen.getByRole('button', { name: inviteText.codeSubmitGuest }))

    expect(captureCodeMock).toHaveBeenCalledWith({ code: '4K7P9QMX', email: 'joao@fabrica.com' })
    expect(markInviteEntryMock).toHaveBeenCalled()
    expect(toastMock.info).toHaveBeenCalledWith(inviteText.codeSaved)
    expect(consumeByCodeMock).not.toHaveBeenCalled()
  })

  it('autenticado: aceita direto pelo código, sem guardar o par', async () => {
    useAuthStore.getState().setSession('tok', { id: 'u1', email: 'joao@fabrica.com', name: 'João' } as never, { remember: false })

    preencher('joao@fabrica.com', '4K7P-9QMX')
    fireEvent.click(screen.getByRole('button', { name: inviteText.codeSubmitAuthed }))

    await waitFor(() => expect(consumeByCodeMock).toHaveBeenCalledWith('4K7P9QMX', 'joao@fabrica.com'))
    expect(captureCodeMock).not.toHaveBeenCalled()
    await waitFor(() => expect(navigateMock).toHaveBeenCalledWith('/'))
  })
})
