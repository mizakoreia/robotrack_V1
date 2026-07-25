import { describe, it, expect } from 'vitest'
import { formatInviteCode, isCompleteInviteCode, normalizeInviteCode } from '../code'

// invite-by-code — normalização tolerante do código no cliente. Espelha o backend
// (Crockford, sem I/L/O/U). Digitar no galpão erra: a tolerância é requisito.
describe('normalizeInviteCode', () => {
  it('sobe para maiúsculas, remove hífen e espaço', () => {
    expect(normalizeInviteCode('4k7p-9qmx')).toBe('4K7P9QMX')
    expect(normalizeInviteCode(' 4k7p 9qmx ')).toBe('4K7P9QMX')
  })

  it('mapeia os ambíguos de leitura (I/L→1, O→0)', () => {
    expect(normalizeInviteCode('ILO0')).toBe('1100')
  })

  it('descarta caracteres fora do alfabeto e limita a 8', () => {
    expect(normalizeInviteCode('4K7P9QMX99')).toBe('4K7P9QMX')
    expect(normalizeInviteCode('4K7P!@#9QMX')).toBe('4K7P9QMX')
  })
})

describe('formatInviteCode', () => {
  it('insere o hífen depois de 4 chars', () => {
    expect(formatInviteCode('4k7p9qmx')).toBe('4K7P-9QMX')
    expect(formatInviteCode('4k7')).toBe('4K7')
    expect(formatInviteCode('4k7p')).toBe('4K7P')
    expect(formatInviteCode('4k7p9')).toBe('4K7P-9')
  })
})

describe('isCompleteInviteCode', () => {
  it('true só com 8 chars canônicos', () => {
    expect(isCompleteInviteCode('4K7P-9QMX')).toBe(true)
    expect(isCompleteInviteCode('4k7p9qmx')).toBe(true)
    expect(isCompleteInviteCode('4K7P-9QM')).toBe(false)
  })
})
