import { describe, it, expect } from 'vitest'
import { authService } from '../auth'
import { authApi } from '../endpoints'

// A versão anterior deste arquivo definia um objeto mock e então afirmava que
// esse mesmo objeto tinha os métodos que ela acabara de escrever nele — verde
// sem tocar em código de produção. Aqui se asserta a superfície real.
describe('superfície de autenticação', () => {
  it('expõe o fluxo de OAuth e de sessão', () => {
    expect(typeof authService.getGoogleAuthUrl).toBe('function')
    expect(typeof authService.handleOAuthCallback).toBe('function')
    expect(typeof authService.checkSessionStatus).toBe('function')
    expect(typeof authService.refreshAccessToken).toBe('function')
    expect(typeof authService.logout).toBe('function')
  })

  it('não expõe mais nada do magic-login de 6 dígitos', () => {
    const removidos = [
      'requestMagicLogin',
      'validateMagicCode',
      'preRegister',
      'verifyPreRegisterCode',
      'completeRegistration',
    ]

    removidos.forEach((metodo) => {
      expect(authService[metodo as keyof typeof authService]).toBeUndefined()
    })
  })

  it('authApi não expõe mais os endpoints de código', () => {
    expect('requestMagicCode' in authApi).toBe(false)
    expect('validateMagicCode' in authApi).toBe(false)
    expect('canResendCode' in authApi).toBe(false)
    expect(typeof authApi.getGoogleAuthUrl).toBe('function')
  })
})
