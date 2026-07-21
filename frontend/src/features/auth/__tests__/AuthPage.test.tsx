import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, fireEvent, waitFor } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'

// identity-and-auth 5.5 — comportamento da tela única de login/cadastro (§3.1).
// As falhas a caçar: a alternância remontar o formulário e apagar o que o usuário
// já digitou; uma senha curta chegar à rede; um 401 apagar o e-mail junto com a
// senha; e o cadastro sem nome sair em silêncio (campo obrigatório sem mensagem).

const { loginMock, registerMock, toastMock } = vi.hoisted(() => ({
  loginMock: vi.fn(),
  registerMock: vi.fn(),
  toastMock: { warning: vi.fn(), error: vi.fn(), success: vi.fn(), info: vi.fn() },
}))

vi.mock('../../../lib/api/endpoints', () => ({
  authApi: {
    login: loginMock,
    register: registerMock,
    googleRedirectUrl: () => 'http://localhost:3000/users/auth/google_oauth2?remember_me=false',
    acceptInvite: vi.fn(),
    logout: vi.fn(),
  },
}))

vi.mock('sonner', () => ({ toast: toastMock }))

import { AuthPage } from '../AuthPage'

function renderPage() {
  return render(
    <MemoryRouter initialEntries={['/entrar']}>
      <AuthPage />
    </MemoryRouter>,
  )
}

const emailField = () => screen.getByLabelText('E-mail') as HTMLInputElement
const passwordField = () => screen.getByLabelText('Senha') as HTMLInputElement
const nameField = () => screen.getByLabelText('Nome') as HTMLInputElement

function type(input: HTMLInputElement, value: string) {
  fireEvent.change(input, { target: { value } })
}

describe('AuthPage — tela única de login e cadastro', () => {
  beforeEach(() => {
    loginMock.mockReset()
    registerMock.mockReset()
    Object.values(toastMock).forEach((fn) => fn.mockReset())
    sessionStorage.clear()
    localStorage.clear()
  })

  it('no modo login não há campo Nome; alternar para cadastro o revela', () => {
    renderPage()

    expect(screen.queryByLabelText('Nome')).toBeNull()
    expect(screen.getByLabelText('Manter conectado')).toBeInTheDocument()

    fireEvent.click(screen.getByRole('button', { name: 'Criar conta' }))

    expect(nameField()).toBeInTheDocument()
    expect(nameField()).toBeRequired()
  })

  it('o e-mail digitado sobrevive à alternância entre os modos', () => {
    renderPage()
    type(emailField(), 'ana@fabrica.com')

    fireEvent.click(screen.getByRole('button', { name: 'Criar conta' }))

    expect(emailField().value).toBe('ana@fabrica.com')
  })

  it('senha de 5 caracteres NÃO dispara requisição e avisa o mínimo de 6', async () => {
    renderPage()
    type(emailField(), 'ana@fabrica.com')
    type(passwordField(), 'abcde')

    fireEvent.click(screen.getByRole('button', { name: 'Entrar' }))

    await waitFor(() => {
      expect(screen.getByText(/ao menos 6 caracteres/i)).toBeInTheDocument()
    })
    expect(loginMock).not.toHaveBeenCalled()
    expect(registerMock).not.toHaveBeenCalled()
  })

  it('401 no login limpa APENAS a senha e mantém o e-mail', async () => {
    loginMock.mockRejectedValue({ response: { status: 401 } })
    renderPage()
    type(emailField(), 'ana@fabrica.com')
    type(passwordField(), 'senha123')

    fireEvent.click(screen.getByRole('button', { name: 'Entrar' }))

    await waitFor(() => {
      expect(screen.getByText('E-mail ou senha inválidos.')).toBeInTheDocument()
    })
    expect(loginMock).toHaveBeenCalledTimes(1)
    expect(passwordField().value).toBe('')
    expect(emailField().value).toBe('ana@fabrica.com')
  })

  it('409 de e-mail duplicado aparece no campo de e-mail e PRESERVA a senha', async () => {
    registerMock.mockRejectedValue({ response: { status: 409 } })
    renderPage()
    fireEvent.click(screen.getByRole('button', { name: 'Criar conta' }))
    type(nameField(), 'Ana Souza')
    type(emailField(), 'ana@fabrica.com')
    type(passwordField(), 'senha123')

    fireEvent.click(screen.getByRole('button', { name: 'Criar conta' }))

    await waitFor(() => {
      expect(screen.getByText('Este e-mail já está cadastrado.')).toBeInTheDocument()
    })
    expect(passwordField().value).toBe('senha123')
  })

  it('cadastro sem nome não envia e anuncia o erro por aria-live no campo Nome', async () => {
    renderPage()
    fireEvent.click(screen.getByRole('button', { name: 'Criar conta' }))
    type(emailField(), 'ana@fabrica.com')
    type(passwordField(), 'senha123')

    fireEvent.click(screen.getByRole('button', { name: 'Criar conta' }))

    const aviso = await screen.findByText(/Informe seu nome/i)
    expect(aviso).toHaveAttribute('aria-live', 'polite')
    expect(registerMock).not.toHaveBeenCalled()
  })

  it('o botão do Google é um link de redirect com o remember escolhido', () => {
    renderPage()

    const link = screen.getByRole('link', { name: /Entrar com Google/i })
    expect(link).toHaveAttribute('href', expect.stringContaining('/users/auth/google_oauth2'))
  })
})
