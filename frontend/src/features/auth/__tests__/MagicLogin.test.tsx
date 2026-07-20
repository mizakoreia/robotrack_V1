import { describe, it, expect, vi } from 'vitest'
import React from 'react'
import { render } from '@testing-library/react'
import { MagicLogin } from '../MagicLogin'

// Mock do useAuth
vi.mock('@/hooks/useAuth', () => ({
  useAuth: () => ({
    loginMethod: 'email',
    identifier: '',
    isLoading: false,
    error: null,
    setLoginMethod: vi.fn(),
    setIdentifier: vi.fn(),
    clearError: vi.fn(),
    requestMagicLogin: vi.fn(),
    loginWithGoogle: vi.fn(),
    loginWithFacebook: vi.fn()
  })
}))

describe('MagicLogin', () => {
  it('deve renderizar sem erros', () => {
    const { container } = render(<MagicLogin onCodeSent={vi.fn()} />)
    expect(container).toBeTruthy()
  })

  it('deve ter título de boas-vindas', () => {
    const { getByText } = render(<MagicLogin onCodeSent={vi.fn()} />)
    expect(getByText('Bem-vindo')).toBeTruthy()
  })

  it('deve ter campo de entrada de email', () => {
    const { getByPlaceholderText } = render(<MagicLogin onCodeSent={vi.fn()} />)
    expect(getByPlaceholderText('seu@email.com')).toBeTruthy()
  })
})