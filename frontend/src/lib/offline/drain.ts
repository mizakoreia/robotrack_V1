import { getResolvedUuids, listMutations, markResolved, transition } from './queue'
import { nextEligible } from './eligibility'
import type { QueueDB } from './db'
import type { QueuedMutation } from './types'

// Drenagem da fila offline (offline-pwa 4.3 / D7-3/D7-4). Laço sequencial por
// `seq` restrito pelo grafo, com UMA requisição em voo por vez. Ao 2xx, o item
// vira `done` e seu `resource_uuid` (mais quaisquer uuids que o servidor devolveu)
// entra em `resolved_uuids`, destravando os dependentes. Só entra aqui depois da
// sonda de saúde passar (o chamador/gatilho faz a sonda).
//
// ESCOPO G4: caminho de sucesso + grafo + um-em-voo. A classificação de erro
// (retryable/permanente/conflito/auth), o backoff e a cascata de bloqueio são do
// G5 — aqui um erro devolve o item a `enfileirado` (com attempts++) e PARA o laço,
// para não girar infinito sobre a mesma falha.

export interface SendResult {
  ok: boolean
  status: number
  resolvedUuids?: string[] // uuids que o servidor confirmou nesta resposta (D1/4.2)
}

export interface DrainDeps {
  probe: () => Promise<boolean>
  send: (m: QueuedMutation) => Promise<SendResult>
  db?: QueueDB
  onChange?: () => void
}

export interface DrainOutcome {
  skipped: boolean
  sent: number
}

// Um passo de drenagem por vez no processo (o líder entre abas é do G6). Sem este
// guard, dois gatilhos concorrentes (online + timer) enviariam o mesmo item duas
// vezes.
let draining = false

export async function drainQueue(deps: DrainDeps): Promise<DrainOutcome> {
  if (draining) return { skipped: true, sent: 0 }
  draining = true
  try {
    if (!(await deps.probe())) return { skipped: true, sent: 0 }

    let sent = 0
    for (;;) {
      const resolved = await getResolvedUuids(deps.db)
      const items = await listMutations(undefined, deps.db)
      const next = nextEligible(items, resolved)
      if (!next) break

      await transition(next.id, 'inflight', {}, deps.db)
      deps.onChange?.()

      let res: SendResult
      try {
        res = await deps.send(next)
      } catch {
        res = { ok: false, status: 0 }
      }

      if (res.ok) {
        await transition(next.id, 'done', { last_error: null }, deps.db)
        await markResolved(next.resource_uuid, { db: deps.db })
        for (const uuid of res.resolvedUuids ?? []) await markResolved(uuid, { db: deps.db })
        sent += 1
        deps.onChange?.()
      } else {
        await transition(
          next.id,
          'enqueued',
          { attempts: next.attempts + 1, last_error: `HTTP ${res.status}` },
          deps.db,
        )
        deps.onChange?.()
        break // G5 refina; G4 não gira sobre o erro
      }
    }
    return { skipped: false, sent }
  } finally {
    draining = false
  }
}

// Semeia `resolved_uuids` a partir de uuids lidos do servidor (D1/4.2): uma tarefa
// criada offline contra um robô que JÁ existia no servidor é elegível sem depender
// de nenhuma mutation de criação. Chamado pelos hooks de leitura ao trazer dados.
export async function seedResolvedFromServer(uuids: Iterable<string>, db?: QueueDB): Promise<void> {
  for (const uuid of uuids) await markResolved(uuid, { db })
}

// Só para testes: zera o guard de concorrência entre casos.
export function _resetDrainGuard(): void {
  draining = false
}
