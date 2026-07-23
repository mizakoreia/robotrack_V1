import { openQueueDb, type QueueDB } from './db'

// Eleição de líder da drenagem (offline-pwa 6.1/6.2 / D7-10). Três abas abertas
// produzem UMA requisição por mutation, não três. Caminho primário: `Web Locks`
// (`navigator.locks`) — o browser garante exclusão mútua e libera a lock se a aba
// morre. Fallback (WebKit sem Web Locks): registro `leader` em IndexedDB com
// `expires_at`, renovado; a serialização das transações readwrite sobre o mesmo
// store é o que impede duas abas de se elegerem juntas.

export const DRAIN_LOCK = 'robotrack-queue-drain'
export const LEADER_TTL_MS = 5000

export interface LeaderDeps {
  locks?: LockManager
  db?: QueueDB
  tabId?: string
  now?: () => number
}

export interface LeaderRun<T> {
  ran: boolean // true se ESTA aba era líder e executou
  result?: T
}

// Reivindica a liderança de fallback numa transação readwrite (atômica): sem
// líder / expirado / já é este tab → assume e renova; senão, não é líder.
export async function claimLeaderFallback(db: QueueDB, tabId: string, now: number): Promise<boolean> {
  const tx = db.transaction('leader', 'readwrite')
  const rec = await tx.store.get('leader')
  let isLeader = false
  if (!rec || rec.expires_at <= now || rec.tabId === tabId) {
    await tx.store.put({ key: 'leader', tabId, expires_at: now + LEADER_TTL_MS })
    isLeader = true
  }
  await tx.done
  return isLeader
}

export async function runAsLeader<T>(fn: () => Promise<T>, deps: LeaderDeps = {}): Promise<LeaderRun<T>> {
  const locks = deps.locks ?? (typeof navigator !== 'undefined' ? navigator.locks : undefined)

  if (locks?.request) {
    // `ifAvailable`: se outra aba segura a lock, `lock` vem null e não bloqueamos.
    return await locks.request(
      DRAIN_LOCK,
      { mode: 'exclusive', ifAvailable: true },
      async (lock): Promise<LeaderRun<T>> => {
        if (!lock) return { ran: false }
        return { ran: true, result: await fn() }
      },
    )
  }

  // Fallback IndexedDB.
  const db = deps.db ?? (await openQueueDb())
  const tabId = deps.tabId ?? 'tab'
  const now = deps.now ? deps.now() : Date.now()
  const isLeader = await claimLeaderFallback(db, tabId, now)
  if (!isLeader) return { ran: false }
  return { ran: true, result: await fn() }
}
