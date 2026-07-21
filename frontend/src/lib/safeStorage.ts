// safeStorage (identity-and-auth 6.2 / D4.9). Toda leitura/escrita de storage é
// protegida contra exceção — Safari em modo privado, bloqueadores, iframe com
// storage particionado podem fazer `localStorage.setItem` lançar. Quando o
// storage real falha, cai para um Map em memória (não sobrevive a reload nem ao
// redirect do Google, mas o login NÃO trava).

export type StorageKind = 'local' | 'session'

const memory = new Map<string, string>()
const memKey = (kind: StorageKind, key: string) => `${kind}:${key}`

function realStorage(kind: StorageKind): Storage | null {
  try {
    const s = kind === 'local' ? window.localStorage : window.sessionStorage
    const probe = '__rt_probe__'
    s.setItem(probe, '1')
    s.removeItem(probe)
    return s
  } catch {
    return null
  }
}

export const safeStorage = {
  get(kind: StorageKind, key: string): string | null {
    try {
      const s = realStorage(kind)
      if (s) return s.getItem(key)
    } catch {
      /* cai para memória */
    }
    return memory.get(memKey(kind, key)) ?? null
  },

  // Devolve `true` se persistiu no storage REAL; `false` se caiu para memória.
  set(kind: StorageKind, key: string, value: string): boolean {
    try {
      const s = realStorage(kind)
      if (s) {
        s.setItem(key, value)
        memory.delete(memKey(kind, key))
        return true
      }
    } catch {
      /* cai para memória */
    }
    memory.set(memKey(kind, key), value)
    return false
  },

  remove(kind: StorageKind, key: string): void {
    try {
      realStorage(kind)?.removeItem(key)
    } catch {
      /* ignore */
    }
    memory.delete(memKey(kind, key))
  },
}

// Handshake com o storage correndo contra um timeout (§3.1): o acesso ao storage
// pode, em ambientes exóticos, pendurar. `withStorageTimeout` garante que o fluxo
// de login prossiga em no máximo `ms` — se estourar, resolve `false` (o chamador
// segue com storage em memória e avisa o usuário). O login NUNCA fica preso.
export function withStorageTimeout<T>(fn: () => T, ms = 1500): Promise<{ value: T | null; timedOut: boolean }> {
  return new Promise((resolve) => {
    let settled = false
    const timer = setTimeout(() => {
      if (settled) return
      settled = true
      resolve({ value: null, timedOut: true })
    }, ms)

    // A operação em si é síncrona, mas a envolvemos numa microtask para que um
    // storage que pendure de fato perca a corrida para o timer.
    Promise.resolve()
      .then(fn)
      .then((value) => {
        if (settled) return
        settled = true
        clearTimeout(timer)
        resolve({ value, timedOut: false })
      })
      .catch(() => {
        if (settled) return
        settled = true
        clearTimeout(timer)
        resolve({ value: null, timedOut: true })
      })
  })
}
