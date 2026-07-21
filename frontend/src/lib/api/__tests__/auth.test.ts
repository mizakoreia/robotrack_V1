import { describe, it, expect } from 'vitest'
import { authApi } from '../endpoints'

// Superfície de autenticação (identity-and-auth). A do template (OAuth por URL
// XHR + refresh token + magic-login) deu lugar a: cadastro/login por senha,
// logout que revoga, renovação explícita, e Google por REDIRECT de página
// inteira (não um endpoint XHR).
describe('superfície de autenticação (authApi)', () => {
  it('expõe cadastro, login, logout, renovação e me', () => {
    expect(typeof authApi.register).toBe('function')
    expect(typeof authApi.login).toBe('function')
    expect(typeof authApi.logout).toBe('function')
    expect(typeof authApi.renew).toBe('function')
    expect(typeof authApi.me).toBe('function')
  })

  it('o Google é um REDIRECT, não um endpoint XHR', () => {
    expect(typeof authApi.googleRedirectUrl).toBe('function')
    const url = authApi.googleRedirectUrl(true)
    expect(url).toContain('/users/auth/google_oauth2')
    expect(url).toContain('remember_me=true')
    // Não há mais fetch de URL de OAuth nem troca de code.
    expect('getGoogleAuthUrl' in authApi).toBe(false)
    expect('handleOAuthCallback' in authApi).toBe(false)
  })

  it('não há mais refresh token nem magic-login', () => {
    expect('refresh' in authApi).toBe(false)
    expect('getSessionStatus' in authApi).toBe(false)
    for (const metodo of ['requestMagicCode', 'validateMagicCode', 'canResendCode', 'preRegister']) {
      expect(metodo in authApi).toBe(false)
    }
  })

  it('expõe o repasse do token de convite', () => {
    expect(typeof authApi.acceptInvite).toBe('function')
  })
})
