import { describe, it, expect, vi } from 'vitest'
import React, { useEffect } from 'react'
import { render, fireEvent, waitFor } from '@testing-library/react'
import { useAuth } from '@/hooks/useAuth'
import { useAuthStore } from '@/store/authStore'
import { authService } from '@/lib/api/auth'

function TestHarness({ method, identifier }: { method: 'email' | 'whatsapp'; identifier: string }) {
  const { setLoginMethod, setIdentifier, requestMagicLogin } = useAuth()
  useEffect(() => {
    setLoginMethod(method)
    setIdentifier(identifier)
  }, [method, identifier])
  return (
    <button onClick={() => requestMagicLogin()} data-testid="trigger">
      trigger
    </button>
  )
}

describe('requestMagicLogin payload normalization', () => {
  it('envia email sem alterar', async () => {
    useAuthStore.setState({ loginMethod: 'email', identifier: '', error: null })
    const spy = vi.spyOn(authService, 'requestMagicLogin').mockResolvedValue({
      success: true,
      message: 'ok',
      identifier: 'user@example.com',
      method: 'email',
    } as any)

    const { getByTestId } = render(<TestHarness method="email" identifier="user@example.com" />)
    fireEvent.click(getByTestId('trigger'))

    await waitFor(() => {
      expect(spy).toHaveBeenCalled()
    })
    const payload = spy.mock.calls[0][0]
    expect(payload).toEqual({ identifier: 'user@example.com', method: 'email' })
    spy.mockRestore()
  })

  it('normaliza whatsapp removendo não dígitos', async () => {
    useAuthStore.setState({ loginMethod: 'whatsapp', identifier: '', error: null })
    const spy = vi.spyOn(authService, 'requestMagicLogin').mockResolvedValue({
      success: true,
      message: 'ok',
      identifier: '5511999999999',
      method: 'whatsapp',
    } as any)

    const { getByTestId } = render(<TestHarness method="whatsapp" identifier="55 (11) 99999-9999" />)
    fireEvent.click(getByTestId('trigger'))

    await waitFor(() => {
      expect(spy).toHaveBeenCalled()
    })
    const payload = spy.mock.calls[0][0]
    expect(payload).toEqual({ identifier: '5511999999999', method: 'whatsapp' })
    spy.mockRestore()
  })
})