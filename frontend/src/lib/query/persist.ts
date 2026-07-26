import { dehydrate, hydrate, type QueryClient, type QueryKey } from '@tanstack/react-query'
import { openDB, type IDBPDatabase } from 'idb'
import { useAuthStore } from '../../store/authStore'

// Persistência do CACHE DE LEITURA do React Query em IndexedDB (offline-pwa,
// "questão aberta nº 3" do design — deliberadamente adiada na Onda D7, agora
// fechada como fix). Sem ela, um reload em modo avião subia o app com o cache
// VAZIO: as telas já visitadas online caíam no estado de erro ("Não foi possível
// carregar…") em vez de mostrar o que foi carregado. Aqui o cache é desidratado
// para IndexedDB e reidratado no boot, ANTES das queries rodarem.
//
// SEGURANÇA (a razão de o design ter adiado isto): o cache não pode vazar dado de
// outro tenant/sessão no dispositivo. Duas travas:
//   1. O snapshot é ESCOPADO À SESSÃO (hash do access token). No boot, se o token
//      corrente não bate com o do snapshot — outra pessoa logou, ou ninguém está
//      logado — o snapshot é DESCARTADO, não reidratado. Um 401 (logout implícito)
//      limpa o token do storage; o próximo boot então purga.
//   2. Os pontos de descarte de tenant já existentes (troca de workspace, revogação
//      de acesso, logout) chamam `purgeQueryCache`/`persistQueryCacheNow` para o
//      disco acompanhar o `queryClient.clear()` da memória.
// O documento do relatório (chave `report`) e a busca (`search`) NÃO são
// persistidos: o relatório é inteiro-ou-nada do servidor (§4.3) e a busca é
// transitória.

const DB_NAME = 'robotrack-query-cache'
const STORE = 'snapshot'
const KEY = 'current'
// Bump manual quando o formato dos DTOs mudar de forma incompatível: invalida
// snapshots antigos sem depender de maxAge.
const PERSIST_VERSION = 1
const MAX_AGE_MS = 7 * 24 * 60 * 60 * 1000 // 7 dias
const SAVE_THROTTLE_MS = 2000

interface Snapshot {
  v: number
  session: string
  savedAt: number
  state: ReturnType<typeof dehydrate>
}

let dbPromise: Promise<IDBPDatabase> | null = null
function getDb(): Promise<IDBPDatabase> {
  if (!dbPromise) {
    dbPromise = openDB(DB_NAME, 1, {
      upgrade(db) {
        if (!db.objectStoreNames.contains(STORE)) db.createObjectStore(STORE)
      },
    })
  }
  return dbPromise
}

// Hash pequeno e estável do token. NÃO é fronteira de segurança (essa mora no
// servidor/RLS); só escopa o snapshot a uma sessão para não reidratar cache de
// outra pessoa. Guardar o hash (e não o token) evita duplicar a credencial.
function sessionKey(): string | null {
  const token = useAuthStore.getState().accessToken
  if (!token) return null
  let h = 0
  for (let i = 0; i < token.length; i++) h = (Math.imul(h, 31) + token.charCodeAt(i)) | 0
  return String(h >>> 0)
}

function isPersistable(queryKey: QueryKey): boolean {
  return Array.isArray(queryKey) && !queryKey.some((p) => p === 'report' || p === 'search')
}

function withTimeout<T>(p: Promise<T>, ms: number): Promise<T | undefined> {
  return new Promise((resolve) => {
    const t = setTimeout(() => resolve(undefined), ms)
    p.then((v) => {
      clearTimeout(t)
      resolve(v)
    }).catch(() => {
      clearTimeout(t)
      resolve(undefined)
    })
  })
}

// Reidrata o cache no boot. Resolve SEMPRE (nunca lança nem pendura): IndexedDB
// bloqueado/ausente → segue sem cache reidratado; o app abre igual.
export async function restoreQueryCache(client: QueryClient): Promise<void> {
  const current = sessionKey()
  if (!current) {
    // Deslogado (ou 401 já limpou o token): nada a reidratar e o snapshot de
    // qualquer sessão anterior é descartado.
    await purgeQueryCache()
    return
  }
  try {
    const rec = (await withTimeout(getDb().then((d) => d.get(STORE, KEY)), 1500)) as Snapshot | undefined
    if (!rec) return
    if (rec.v !== PERSIST_VERSION || rec.session !== current || Date.now() - rec.savedAt > MAX_AGE_MS) {
      await purgeQueryCache()
      return
    }
    hydrate(client, rec.state)
  } catch {
    /* IDB indisponível: sem cache reidratado */
  }
}

async function saveNow(client: QueryClient): Promise<void> {
  const current = sessionKey()
  if (!current) {
    // Sessão encerrada: o disco não pode segurar o cache do dono anterior.
    await purgeQueryCache()
    return
  }
  try {
    const state = dehydrate(client, {
      shouldDehydrateQuery: (q) => q.state.status === 'success' && isPersistable(q.queryKey),
      shouldDehydrateMutation: () => false, // a fila offline (idb próprio) é a fonte das escritas
    })
    const snapshot: Snapshot = { v: PERSIST_VERSION, session: current, savedAt: Date.now(), state }
    const db = await getDb()
    await db.put(STORE, snapshot, KEY)
  } catch {
    /* IDB indisponível: sem persistência (o app segue, só perde leitura offline) */
  }
}

// Gravação imediata (após um descarte de segurança, para o disco não ficar atrás
// da memória). Exposto para `accessRevoked`.
export function persistQueryCacheNow(client: QueryClient): Promise<void> {
  return saveNow(client)
}

// Assina o cache e persiste com throttle (bordo de descida). Também descarrega no
// `pagehide`/ocultar aba, para durar até um fechamento abrupto. Devolve o desligamento.
export function startQueryPersist(client: QueryClient): () => void {
  let timer: ReturnType<typeof setTimeout> | null = null
  const schedule = () => {
    if (timer) return
    timer = setTimeout(() => {
      timer = null
      void saveNow(client)
    }, SAVE_THROTTLE_MS)
  }
  const flush = () => {
    if (timer) {
      clearTimeout(timer)
      timer = null
    }
    void saveNow(client)
  }
  const onVisibility = () => {
    if (typeof document !== 'undefined' && document.visibilityState === 'hidden') flush()
  }

  const unsub = client.getQueryCache().subscribe(schedule)
  if (typeof window !== 'undefined') {
    window.addEventListener('pagehide', flush)
    document.addEventListener('visibilitychange', onVisibility)
  }

  return () => {
    unsub()
    if (typeof window !== 'undefined') {
      window.removeEventListener('pagehide', flush)
      document.removeEventListener('visibilitychange', onVisibility)
    }
    if (timer) {
      clearTimeout(timer)
      timer = null
    }
  }
}

// Apaga o snapshot do disco. Chamado nos descartes de tenant (logout, troca de
// workspace) e quando a sessão corrente não bate com a persistida.
export async function purgeQueryCache(): Promise<void> {
  try {
    const db = await getDb()
    await db.delete(STORE, KEY)
  } catch {
    /* IDB indisponível: nada a apagar */
  }
}

// Só para testes: descarta o singleton para reabrir contra uma factory nova.
export function _resetPersistDbSingleton(): void {
  dbPromise = null
}
