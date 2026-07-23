import { create } from 'zustand'
import { safeStorage, type StorageKind } from '../lib/safeStorage'
import { queryClient } from '../lib/queryClient'

// Fonte ÚNICA do token no cliente (identity-and-auth 6.1 / D4.9). O template
// mantinha `localStorage['token']` E `localStorage['auth-storage']` (zustand
// persist) sincronizados na mão; aqui o dono é este store e o meio de
// armazenamento é ESCOLHIDO conforme "manter conectado":
//   - marcado   → localStorage (sobrevive ao reinício do navegador);
//   - desmarcado → sessionStorage (some ao fechar a aba).
// Ao autenticar, o storage do modo OPOSTO é limpo, para não restaurar uma
// sessão antiga numa aba nova.

export interface AuthUser {
  id: string
  name?: string
  email?: string
  avatar_url?: string | null
  // Campos herdados do template, lidos por telas legadas (Dashboard/Users/Topbar/
  // Profile). Fora do escopo de identity-and-auth (a entidade do servidor expõe
  // só id/name/email/avatar_url); mantidos opcionais para compat de compilação.
  user_type?: string
  is_og?: boolean
  phone?: string
}

const SESSION_KEY = 'robotrack.session'

interface StoredSession {
  accessToken: string
  user: AuthUser | null
}

interface AuthState {
  isAuthenticated: boolean
  accessToken: string | null
  user: AuthUser | null
  storageKind: StorageKind
  // `true` quando o token só existe em memória (storage bloqueado): a sessão não
  // sobrevive a reload nem ao redirect do Google.
  memoryOnly: boolean

  setSession: (token: string, user: AuthUser | null, opts: { remember: boolean }) => void
  setToken: (token: string) => void
  setUser: (user: AuthUser | null) => void
  clearSession: () => void

  // Aliases de compatibilidade com componentes existentes.
  logout: () => void
  setAuth: (tokens: { accessToken: string }, user: AuthUser | null) => void
}

function persistSession(kind: StorageKind, token: string, user: AuthUser | null): boolean {
  const other: StorageKind = kind === 'local' ? 'session' : 'local'
  safeStorage.remove(other, SESSION_KEY)
  return safeStorage.set(kind, SESSION_KEY, JSON.stringify({ accessToken: token, user } satisfies StoredSession))
}

function wipe(): void {
  safeStorage.remove('local', SESSION_KEY)
  safeStorage.remove('session', SESSION_KEY)
}

// Hidratação inicial: procura a sessão em localStorage e, se não houver, em
// sessionStorage. O `kind` encontrado vira o meio corrente.
function hydrate(): Pick<AuthState, 'isAuthenticated' | 'accessToken' | 'user' | 'storageKind' | 'memoryOnly'> {
  for (const kind of ['local', 'session'] as StorageKind[]) {
    const raw = safeStorage.get(kind, SESSION_KEY)
    if (!raw) continue
    try {
      const parsed = JSON.parse(raw) as StoredSession
      if (parsed?.accessToken) {
        return {
          isAuthenticated: true,
          accessToken: parsed.accessToken,
          user: parsed.user ?? null,
          storageKind: kind,
          memoryOnly: false,
        }
      }
    } catch {
      /* sessão corrompida: ignora */
    }
  }
  return { isAuthenticated: false, accessToken: null, user: null, storageKind: 'session', memoryOnly: false }
}

// app-shell-navigation 2.2 (D-E) — migração de boot das chaves LEGADAS do
// template (`access_token`/`token` cruas em localStorage). Só migra se ainda não
// há sessão nova; escreve a sessão nova ANTES de remover as chaves legadas, para
// nunca perder a única cópia do token. Segundo boot não altera nada.
function migrateLegacyToken(): void {
  try {
    if (safeStorage.get('local', SESSION_KEY) || safeStorage.get('session', SESSION_KEY)) return
    const legacy = safeStorage.get('local', 'access_token') || safeStorage.get('local', 'token')
    if (!legacy) return
    persistSession('local', legacy, null) // escreve a nova sessão primeiro
    safeStorage.remove('local', 'access_token')
    safeStorage.remove('local', 'token')
  } catch {
    /* armazenamento bloqueado: nada a migrar */
  }
}

migrateLegacyToken()

export const useAuthStore = create<AuthState>((set, get) => ({
  ...hydrate(),

  setSession: (token, user, { remember }) => {
    const kind: StorageKind = remember ? 'local' : 'session'
    const persisted = persistSession(kind, token, user)
    set({ isAuthenticated: true, accessToken: token, user, storageKind: kind, memoryOnly: !persisted })
  },

  setToken: (token) => {
    const { storageKind, user } = get()
    persistSession(storageKind, token, user)
    set({ accessToken: token, isAuthenticated: true })
  },

  setUser: (user) => {
    const { storageKind, accessToken } = get()
    if (accessToken) persistSession(storageKind, accessToken, user)
    set({ user })
  },

  clearSession: () => {
    wipe()
    set({ isAuthenticated: false, accessToken: null, user: null, memoryOnly: false })
  },

  // app-shell-navigation 2.3 (D-E) — sair DESCARTA o cache do React Query junto,
  // como a troca de workspace (5.4): o próximo usuário na mesma aba nunca vê o
  // dado do anterior. A requisição seguinte sai sem `Authorization`.
  logout: () => {
    get().clearSession()
    queryClient.clear()
  },
  setAuth: (tokens, user) => get().setSession(tokens.accessToken, user, { remember: true }),
}))
