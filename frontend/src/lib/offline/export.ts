import { openQueueDb, DB_VERSION, type QueueDB } from './db'
import { listMutations } from './queue'

// Exportação da fila (offline-pwa 8.3). Rede de segurança ANTES de qualquer
// migração de esquema (8.4): mesmo que uma migração quarentene itens, o usuário
// recupera o conteúdo — inclusive o avanço registrado às 14h. É um dump legível,
// não um formato interno.

export interface QueueExport {
  exported_at: string
  db_version: number
  mutations: unknown[]
  resolved_uuids: unknown[]
}

export async function exportQueue(db?: QueueDB, nowIso?: string): Promise<QueueExport> {
  const d = db ?? (await openQueueDb())
  const mutations = await listMutations(undefined, d)
  const resolved = await d.getAll('resolved_uuids')
  return {
    exported_at: nowIso ?? new Date().toISOString(),
    db_version: DB_VERSION,
    mutations,
    resolved_uuids: resolved,
  }
}

export async function exportQueueJson(db?: QueueDB, nowIso?: string): Promise<string> {
  return JSON.stringify(await exportQueue(db, nowIso), null, 2)
}

// Dispara o download do backup na UI de diagnóstico. Injetável para teste.
export async function downloadQueueExport(
  deps: {
    createUrl?: (b: Blob) => string
    revokeUrl?: (u: string) => void
    anchor?: () => { click: () => void; href?: string; download?: string }
    nowIso?: string
    db?: QueueDB
  } = {},
): Promise<void> {
  const json = await exportQueueJson(deps.db, deps.nowIso)
  const blob = new Blob([json], { type: 'application/json' })
  const createUrl = deps.createUrl ?? ((b) => URL.createObjectURL(b))
  const revokeUrl = deps.revokeUrl ?? ((u) => URL.revokeObjectURL(u))
  const makeAnchor = deps.anchor ?? (() => document.createElement('a'))

  const url = createUrl(blob)
  const a = makeAnchor()
  a.href = url
  a.download = `robotrack-fila-offline-${(deps.nowIso ?? new Date().toISOString()).slice(0, 10)}.json`
  a.click()
  revokeUrl(url)
}
