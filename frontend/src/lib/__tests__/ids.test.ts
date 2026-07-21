import { describe, expect, it, afterEach } from 'vitest'
import { isValidId, newId, UUID_RE } from '../ids'

// commissioning-hierarchy 6.6 (D1) — o fallback é o ponto: se ele gerasse
// "string qualquer", todo POST criado offline voltaria 422 ao sincronizar,
// porque o servidor valida UUID v1–v8 RFC 4122 (Hierarchy::IdValidator).
describe('newId', () => {
  const original = globalThis.crypto

  afterEach(() => {
    Object.defineProperty(globalThis, 'crypto', { value: original, configurable: true })
  })

  it('usa crypto.randomUUID quando existe', () => {
    const id = newId()
    expect(isValidId(id)).toBe(true)
  })

  it('sem randomUUID (contexto inseguro / Safari antigo), o fallback gera UUID v4 VÁLIDO', () => {
    Object.defineProperty(globalThis, 'crypto', {
      value: { getRandomValues: original.getRandomValues.bind(original) },
      configurable: true,
    })

    const ids = Array.from({ length: 50 }, () => newId())
    ids.forEach((id) => {
      expect(id).toMatch(UUID_RE)
      expect(id[14]).toBe('4')
      expect(['8', '9', 'a', 'b']).toContain(id[19])
    })
    expect(new Set(ids).size).toBe(50)
  })

  it('sem crypto nenhum, ainda gera UUID válido', () => {
    Object.defineProperty(globalThis, 'crypto', { value: undefined, configurable: true })
    expect(isValidId(newId())).toBe(true)
  })

  it('rejeita o UUID nulo e formatos tortos (mesma regra do servidor)', () => {
    expect(isValidId('00000000-0000-0000-0000-000000000000')).toBe(false)
    expect(isValidId('abc')).toBe(false)
    expect(isValidId('12345678-1234-4234-c234-123456789012')).toBe(false)
  })
})
