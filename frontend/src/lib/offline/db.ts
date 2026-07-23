import { openDB, type DBSchema, type IDBPDatabase } from 'idb'
import type { QueuedMutation, ResolvedUuid } from './types'

// Banco IndexedDB da fila offline (offline-pwa 3.1 / D7-3). `idb` deixa o esquema
// versionado e as transações legíveis; o guard `no-heavy-deps` não o barra (~1KB).
//
// Object stores:
//   mutations      keyPath 'id' (uuid do cliente). Índices:
//                    by_state_and_seq [state, seq] — a ordem de drenagem elegível
//                    by_workspace     workspace_id  — projeção escopada por WS (D9)
//   resolved_uuids keyPath 'uuid' — conjunto persistido do que o servidor confirmou
//   meta           keyPath 'key'  — contador de `seq` (ver nota abaixo)
//
// NOTA sobre `seq`: o design pede `seq` "autoIncrement do object store", mas o
// keyPath do store é `id` (o uuid do cliente) e o IndexedDB não faz keyPath +
// autoIncrement no mesmo store. Mintamos `seq` de um contador monotônico em `meta`,
// incrementado na MESMA transação readwrite do insert — mesmo comportamento
// observável (monotônico por dispositivo, sobrevive a reabertura).

export const DB_NAME = 'robotrack'
export const DB_VERSION = 2

interface RobotrackDB extends DBSchema {
  mutations: {
    key: string
    value: QueuedMutation
    indexes: { by_state_and_seq: [string, number]; by_workspace: string }
  }
  resolved_uuids: {
    key: string
    value: ResolvedUuid
  }
  meta: {
    key: string
    value: { key: string; value: number }
  }
  // Eleição de líder de fallback (offline-pwa 6.2), para browsers sem Web Locks
  // (WebKit antigo). Registro único `leader` com dono e expiração.
  leader: {
    key: string
    value: { key: string; tabId: string; expires_at: number }
  }
}

export type QueueDB = IDBPDatabase<RobotrackDB>

// Um registro é reconhecível quando tem as chaves estruturais mínimas. Um item
// gravado por um esquema anterior e não migrável cai fora deste guard.
function isRecognizable(rec: unknown): rec is QueuedMutation {
  if (!rec || typeof rec !== 'object') return false
  const r = rec as Record<string, unknown>
  return (
    typeof r.id === 'string' &&
    typeof r.seq === 'number' &&
    typeof r.kind === 'string' &&
    typeof r.workspace_id === 'string' &&
    Array.isArray(r.depends_on) &&
    typeof r.state === 'string'
  )
}

// Quarentena (3.1): item irreconhecível vira `failed` classe "incompatível" e
// NUNCA é apagado — o conteúdo (ex.: o avanço registrado às 14h) fica recuperável
// pela exportação de diagnóstico (8.3). Chamada no `upgrade` de migrações futuras
// (8.4 liga o bump de versão) e exposta para teste direto.
export async function quarantineIncompatible(db: QueueDB): Promise<number> {
  const tx = db.transaction('mutations', 'readwrite')
  let quarantined = 0
  let cursor = await tx.store.openCursor()
  while (cursor) {
    const rec = cursor.value as unknown
    if (!isRecognizable(rec)) {
      const salvaged = (rec ?? {}) as Record<string, unknown>
      await cursor.update({
        ...(salvaged as object),
        id: typeof salvaged.id === 'string' ? salvaged.id : cursor.primaryKey,
        state: 'failed',
        last_error: 'incompatível: esquema anterior não migrável',
      } as QueuedMutation)
      quarantined += 1
    }
    cursor = await cursor.continue()
  }
  await tx.done
  return quarantined
}

let dbPromise: Promise<QueueDB> | null = null

export function openQueueDb(): Promise<QueueDB> {
  if (!dbPromise) {
    dbPromise = openDB<RobotrackDB>(DB_NAME, DB_VERSION, {
      upgrade(db, oldVersion, _newVersion, tx) {
        if (oldVersion < 1) {
          const mutations = db.createObjectStore('mutations', { keyPath: 'id' })
          mutations.createIndex('by_state_and_seq', ['state', 'seq'])
          mutations.createIndex('by_workspace', 'workspace_id')
          db.createObjectStore('resolved_uuids', { keyPath: 'uuid' })
          db.createObjectStore('meta', { keyPath: 'key' })
        }
        if (oldVersion < 2) {
          // Aditivo: store de líder de fallback. Não toca dados existentes.
          db.createObjectStore('leader', { keyPath: 'key' })
        }
        // Migrações futuras (8.4) quarentenam o irreconhecível ANTES de tocar dados.
        // Em v1 não há base anterior; o gancho fica pronto.
        void tx
      },
    })
  }
  return dbPromise
}

// Só para testes: descarta o singleton para reabrir do zero.
export function _resetQueueDbSingleton(): void {
  dbPromise = null
}
