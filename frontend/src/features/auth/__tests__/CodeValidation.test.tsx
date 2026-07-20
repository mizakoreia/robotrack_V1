import { describe, it, expect, vi } from 'vitest'
import React from 'react'
import { render } from '@testing-library/react'
import { CodeValidation } from '../CodeValidation'

// Mock do useAuth
vi.mock('@/hooks/useAuth', () => ({
  useAuth: () => ({
    validateMagicCode: vi.fn()
  })
}))

// Mock do useAuthStore
vi.mock('@/store/authStore', () => ({
  useAuthStore: () => ({
    loginMethod: 'email'
  })
}))

describe('CodeValidation', () => {
  it('deve renderizar sem erros', () => {
    const { container } = render(
      <CodeValidation 
        email="test@example.com" 
        onBack={vi.fn()} 
        onSuccess={vi.fn()} 
      />
    )
    expect(container).toBeTruthy()
  })

  it('deve ter título de verificação', () => {
    const { getByText } = render(
      <CodeValidation 
        email="test@example.com" 
        onBack={vi.fn()} 
        onSuccess={vi.fn()} 
      />
    )
    expect(getByText('Verificação')).toBeTruthy()
  })

  it('deve mostrar email do usuário', () => {
    const { getByText } = render(
      <CodeValidation 
        email="test@example.com" 
        onBack={vi.fn()} 
        onSuccess={vi.fn()} 
      />
    )
    expect(getByText('Email: test@example.com')).toBeTruthy()
  })
})