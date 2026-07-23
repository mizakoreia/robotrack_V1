import { openQueueDb, type QueueDB } from './db'
import {
  QueueFullError,
  type EnqueueInput,
  type QueuedMutation,
  type MutationState,
  type ResolvedUuid,
} from './types'

// Operações da fila offline (offline-pwa 3.2/3.3 / D7-3/D7-8/D7-12).

export const MAX_ITEMS = 500
export const MAX_BYTES = 5 * 1024 * 1024 // 5 MB

const encoder = new TextEncoder()
const byteSize = (rec: QueuedMutation): number => encoder.encode(JSON.stringify(rec)).length

// Estados que CONTAM para o teto (o que ainda ocupa a fila). `done` é podado; não
// conta. `failed`/`blocked` contam — sobrevivem até decisão do usuário e ocupam
// espaço real.
const COUNTS_TOWARD_CEILING: MutationState[] = ['enqueued', 'inflight', 'failed', 'blocked']

function nowIso(clock?: () => number): string {
  return new Date(clock ? clock() : Date.now()).toISOString()
}

const BYTES_KEY = 'bytes'

// Poda itens `done` (2xx já confirmados): sucesso terminal não precisa persistir.
// Abate o total de bytes em `meta` conforme remove.
export async function pruneDone(db?: QueueDB): Promise<number> {
  const d = db ?? (await openQueueDb())
  const tx = d.transaction(['mutations', 'meta'], 'readwrite')
  const store = tx.objectStore('mutations')
  const meta = tx.objectStore('meta')
  let pruned = 0
  let freed = 0
  let cursor = await store.openCursor()
  while (cursor) {
    if (cursor.value.state === 'done') {
      freed += byteSize(cursor.value)
      await cursor.delete()
      pruned += 1
    }
    cursor = await cursor.continue()
  }
  if (freed > 0) {
    const cur = (await meta.get(BYTES_KEY))?.value ?? 0
    await meta.put({ key: BYTES_KEY, value: Math.max(0, cur - freed) })
  }
  await tx.done
  return pruned
}

// Enfileira uma mutation (D7-8: carimba `recorded_at` no instante da confirmação,
// que é ESTE instante — enqueue é chamado no submit do modal). Atribui `seq`
// monotônico na mesma transação. Rejeita na ENTRADA quando o teto estoura, SEM
// descartar o item mais antigo (D7-12: janela deslizante perderia o avanço das 14h).
export async function enqueueMutation(
  input: EnqueueInput,
  opts: { clock?: () => number; db?: QueueDB } = {},
): Promise<QueuedMutation> {
  const d = opts.db ?? (await openQueueDb())

  // Poda `done` primeiro: eles não ocupam a fila conceitualmente e liberam espaço.
  await pruneDone(d)

  const record: QueuedMutation = {
    id: input.id,
    seq: 0, // atribuído abaixo na transação
    kind: input.kind,
    resource_uuid: input.resource_uuid,
    workspace_id: input.workspace_id,
    method: input.method,
    url: input.url,
    body: input.body,
    depends_on: input.depends_on,
    recorded_at: input.recorded_at ?? nowIso(opts.clock),
    state: 'enqueued',
    attempts: 0,
    next_attempt_at: null,
    last_error: null,
  }

  const tx = d.transaction(['mutations', 'meta'], 'readwrite')
  const mutations = tx.objectStore('mutations')
  const meta = tx.objectStore('meta')

  // Teto verificado DENTRO da transação. `pruneDone` já removeu os `done`, então
  // todo item restante conta para o teto → `count()` é a contagem exata (O(1),
  // sem varrer). O total de bytes é mantido incrementalmente em `meta` (aproxima o
  // crescimento posterior de last_error/attempts, mas mantém o teto de 5MB barato).
  const size = byteSize(record)
  const count = await mutations.count()
  const bytes = (await meta.get(BYTES_KEY))?.value ?? 0
  if (count >= MAX_ITEMS || bytes + size > MAX_BYTES) {
    await tx.done.catch(() => {})
    throw new QueueFullError()
  }

  const curSeq = (await meta.get('seq'))?.value ?? 0
  record.seq = curSeq + 1
  await meta.put({ key: 'seq', value: record.seq })
  await meta.put({ key: BYTES_KEY, value: bytes + size })
  await mutations.put(record)
  await tx.done

  return record
}

// Lista mutations, opcionalmente escopadas por workspace, em ordem de `seq`.
export async function listMutations(workspaceId?: string, db?: QueueDB): Promise<QueuedMutation[]> {
  const d = db ?? (await openQueueDb())
  const all = workspaceId
    ? await d.getAllFromIndex('mutations', 'by_workspace', workspaceId)
    : await d.getAll('mutations')
  return all.sort((a, b) => a.seq - b.seq)
}

export async function countPending(workspaceId?: string, db?: QueueDB): Promise<number> {
  const items = await listMutations(workspaceId, db)
  return items.filter((m) => COUNTS_TOWARD_CEILING.includes(m.state)).length
}

// ── resolved_uuids: o conjunto do que o servidor já confirmou (D7-4) ───────────

export async function markResolved(uuid: string, opts: { clock?: () => number; db?: QueueDB } = {}): Promise<void> {
  const d = opts.db ?? (await openQueueDb())
  const rec: ResolvedUuid = { uuid, at: nowIso(opts.clock) }
  await d.put('resolved_uuids', rec)
}

export async function getResolvedUuids(db?: QueueDB): Promise<Set<string>> {
  const d = db ?? (await openQueueDb())
  const all = await d.getAll('resolved_uuids')
  return new Set(all.map((r) => r.uuid))
}
