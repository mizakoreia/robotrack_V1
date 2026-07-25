import { describe, it, expect, beforeEach } from 'vitest'
import { inviteStore } from '../invite'

// invite-by-code — o par código+e-mail sobrevive ao redirect do Google (mesma
// origem, sessionStorage). Roundtrip e robustez a valor corrompido.
describe('inviteStore código', () => {
  beforeEach(() => {
    sessionStorage.clear()
    inviteStore.clearCode()
  })

  it('grava e lê o par código+e-mail', () => {
    inviteStore.captureCode({ code: '4K7P9QMX', email: 'joao@fabrica.com' })
    expect(inviteStore.readCode()).toEqual({ code: '4K7P9QMX', email: 'joao@fabrica.com' })
  })

  it('sobrevive a uma releitura (simula o retorno do OAuth)', () => {
    inviteStore.captureCode({ code: 'ABCD1234', email: 'ana@fabrica.com' })
    // Nada limpa entre a captura e a leitura — é o que o redirect preserva.
    expect(inviteStore.readCode()?.code).toBe('ABCD1234')
  })

  it('clearCode remove o par', () => {
    inviteStore.captureCode({ code: '4K7P9QMX', email: 'joao@fabrica.com' })
    inviteStore.clearCode()
    expect(inviteStore.readCode()).toBeNull()
  })

  it('valor corrompido no storage é tratado como ausente', () => {
    sessionStorage.setItem('robotrack.invite_code', '{ nao é json')
    expect(inviteStore.readCode()).toBeNull()
  })
})
