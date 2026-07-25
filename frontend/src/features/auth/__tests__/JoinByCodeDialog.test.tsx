import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, fireEvent, waitFor, cleanup } from '@testing-library/react'

// join-workspace-by-code — o diálogo in-app de entrada por código (usuário LOGADO).
// As falhas a caçar: pedir e-mail (não deve — usa o da sessão); formato incompleto
// virar requisição (não deve); e fechar/navegar quando o aceite FALHOU (não deve —
// o diálogo fica aberto com o código para corrigir). O aceite em si é
// `consumeInviteByCode`, reusado e aqui mockado.

const { consumeByCodeMock, navigateMock } = vi.hoisted(() => ({
  consumeByCodeMock: vi.fn<(code: string, email: string) => Promise<boolean>>(),
  navigateMock: vi.fn(),
}))

vi.mock('@/lib/auth/session', () => ({
  consumeInviteByCode: consumeByCodeMock,
}))

vi.mock('react-router-dom', async () => {
  const real = await vi.importActual<typeof import('react-router-dom')>('react-router-dom')
  return { ...real, useNavigate: () => navigateMock }
})

import { JoinByCodeDialog } from '../JoinByCodeDialog'
import { useAuthStore } from '@/store/authStore'
import { inviteText } from '@/lib/i18n/invitations'

function abrir() {
  render(<JoinByCodeDialog open onClose={onCloseMock} />)
}

const onCloseMock = vi.fn()

describe('JoinByCodeDialog', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    cleanup()
    useAuthStore.setState({ user: { id: 'u1', name: 'João', email: 'joao@fabrica.com' }, isAuthenticated: true } as never)
    consumeByCodeMock.mockResolvedValue(true)
  })

  it('mostra o e-mail da sessão como contexto e NÃO oferece campo de e-mail', () => {
    abrir()
    expect(screen.getByText(inviteText.joinByCodeAs('joao@fabrica.com'))).toBeInTheDocument()
    // um único campo editável: o código. Não há input de e-mail.
    expect(screen.getByLabelText(inviteText.codeLabel)).toBeInTheDocument()
    expect(screen.queryByLabelText(inviteText.codeEmailLabel)).toBeNull()
  })

  it('máscara aplica XXXX-XXXX enquanto digita', () => {
    abrir()
    const campo = screen.getByLabelText(inviteText.codeLabel) as HTMLInputElement
    fireEvent.change(campo, { target: { value: 'il0o4k7p' } }) // ambíguos normalizados
    expect(campo.value).toBe('1100-4K7P')
  })

  it('formato incompleto NÃO chama o aceite e mostra erro inline', () => {
    abrir()
    fireEvent.change(screen.getByLabelText(inviteText.codeLabel), { target: { value: '4K7P-9QM' } }) // 7
    fireEvent.click(screen.getByRole('button', { name: inviteText.joinByCodeSubmit }))
    expect(screen.getByText(inviteText.codeInvalidFormat)).toBeInTheDocument()
    expect(consumeByCodeMock).not.toHaveBeenCalled()
  })

  it('sucesso: aceita com o e-mail da sessão, fecha e vai para a Visão Geral', async () => {
    abrir()
    fireEvent.change(screen.getByLabelText(inviteText.codeLabel), { target: { value: '4k7p-9qmx' } })
    fireEvent.click(screen.getByRole('button', { name: inviteText.joinByCodeSubmit }))

    await waitFor(() => expect(consumeByCodeMock).toHaveBeenCalledWith('4K7P9QMX', 'joao@fabrica.com'))
    await waitFor(() => expect(onCloseMock).toHaveBeenCalled())
    expect(navigateMock).toHaveBeenCalledWith('/')
  })

  it('falha: NÃO fecha nem navega (o diálogo fica aberto com o código)', async () => {
    consumeByCodeMock.mockResolvedValue(false)
    abrir()
    fireEvent.change(screen.getByLabelText(inviteText.codeLabel), { target: { value: '4K7P-9QMX' } })
    fireEvent.click(screen.getByRole('button', { name: inviteText.joinByCodeSubmit }))

    await waitFor(() => expect(consumeByCodeMock).toHaveBeenCalled())
    expect(onCloseMock).not.toHaveBeenCalled()
    expect(navigateMock).not.toHaveBeenCalled()
    // botão volta a ficar acionável (busy liberado)
    expect(screen.getByRole('button', { name: inviteText.joinByCodeSubmit })).not.toBeDisabled()
  })

  it('Esc fecha o diálogo', () => {
    abrir()
    fireEvent.keyDown(document, { key: 'Escape' })
    expect(onCloseMock).toHaveBeenCalled()
  })
})
