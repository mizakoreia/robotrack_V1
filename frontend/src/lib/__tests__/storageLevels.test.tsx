import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'
import { render, screen, cleanup, fireEvent } from '@testing-library/react'
import { probeStorageLevel, resetStorageLevelCache, safeStorage } from '../safeStorage'
import { useAuthStore } from '../../store/authStore'
import { StorageWarning } from '../../components/StorageWarning'

// offline-pwa 1.4 (D7-11) — a sonda de nível e a honestidade do login sob
// armazenamento bloqueado. A falha a caçar é a PIOR: `localStorage.setItem`
// lança `QuotaExceededError` no Safari privado e um throw não capturado no boot
// deixa a tela branca. Aqui simulamos os três níveis fazendo os globais lançarem
// e afirmamos que o login CONCLUI (store autenticado) nos três, e que o aviso
// diz a verdade em cada nível.

type Throwing = Pick<Storage, 'getItem' | 'setItem' | 'removeItem' | 'clear' | 'key' | 'length'>

function throwingStorage(): Throwing {
  const boom = () => {
    throw new DOMException('bloqueado', 'QuotaExceededError')
  }
  return { getItem: boom, setItem: boom, removeItem: boom, clear: boom, key: boom, length: 0 }
}

const realLocal = window.localStorage
const realSession = window.sessionStorage

function setStorage(kind: 'local' | 'session', impl: Storage | Throwing) {
  Object.defineProperty(window, kind === 'local' ? 'localStorage' : 'sessionStorage', {
    value: impl,
    configurable: true,
  })
}

// Cada nível é um cenário: quais globais lançam.
function applyLevel(level: 'persistent' | 'session-only' | 'memory-only') {
  setStorage('local', level === 'persistent' ? realLocal : throwingStorage())
  setStorage('session', level === 'memory-only' ? throwingStorage() : realSession)
  resetStorageLevelCache()
}

beforeEach(() => {
  useAuthStore.getState().clearSession()
  safeStorage.remove('session', 'robotrack.storage_warning_dismissed')
})

afterEach(() => {
  cleanup()
  setStorage('local', realLocal)
  setStorage('session', realSession)
  resetStorageLevelCache()
  vi.restoreAllMocks()
})

describe('sonda de nível de armazenamento (1.4)', () => {
  it('localStorage OK → persistent', () => {
    applyLevel('persistent')
    expect(probeStorageLevel()).toBe('persistent')
  })

  it('localStorage bloqueado, sessionStorage OK → session-only (não persistent)', () => {
    applyLevel('session-only')
    expect(probeStorageLevel()).toBe('session-only')
  })

  it('ambos bloqueados → memory-only', () => {
    applyLevel('memory-only')
    expect(probeStorageLevel()).toBe('memory-only')
  })
})

describe('login conclui e não lança em nenhum nível (1.4)', () => {
  const levels = ['persistent', 'session-only', 'memory-only'] as const

  for (const level of levels) {
    it(`nível ${level}: setSession autentica sem exceção`, () => {
      applyLevel(level)
      const spy = vi.spyOn(console, 'error').mockImplementation(() => {})

      // remember=false → meio 'session': persiste em persistent e session-only,
      // e só cai em memória em memory-only. (O caso "manter conectado" sob
      // session-only, que cai em memória de propósito, é o cenário do 8.1.)
      expect(() => {
        useAuthStore.getState().setSession('tok-123', { id: 'u1', name: 'Ana' }, { remember: false })
      }).not.toThrow()

      const s = useAuthStore.getState()
      expect(s.isAuthenticated).toBe(true)
      expect(s.accessToken).toBe('tok-123')
      // memoryOnly só quando NADA persiste (nem sessionStorage).
      expect(s.memoryOnly).toBe(level === 'memory-only')
      // Nenhuma exceção não capturada vazou para o console (proxy da "tela branca").
      expect(spy).not.toHaveBeenCalled()
    })
  }
})

describe('aviso persistente por nível (1.3/1.4)', () => {
  it('persistent → nenhum aviso', () => {
    applyLevel('persistent')
    const { container } = render(<StorageWarning />)
    expect(container).toBeEmptyDOMElement()
  })

  it('session-only → aviso SEM a frase de alterações offline', () => {
    applyLevel('session-only')
    render(<StorageWarning />)
    const msg = screen.getByRole('status').textContent ?? ''
    expect(msg).toContain('a sessão não vai persistir ao fechar')
    expect(msg).not.toContain('sem conexão não serão salvas')
  })

  it('memory-only → aviso COM a frase de alterações offline', () => {
    applyLevel('memory-only')
    render(<StorageWarning />)
    const msg = screen.getByRole('status').textContent ?? ''
    expect(msg).toContain('a sessão não vai persistir ao fechar')
    expect(msg).toContain('e alterações feitas sem conexão não serão salvas')
  })

  it('é dispensável — some ao fechar e não conta como aviso depois', () => {
    applyLevel('session-only')
    const { rerender } = render(<StorageWarning />)
    fireEvent.click(screen.getByRole('button', { name: 'Dispensar aviso' }))
    rerender(<StorageWarning />)
    expect(screen.queryByRole('status')).toBeNull()
  })
})
