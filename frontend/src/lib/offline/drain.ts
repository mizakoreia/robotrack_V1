import { getResolvedUuids, listMutations, markResolved, transition } from './queue'
import { nextEligible } from './eligibility'
import { classifyResponse } from './classify'
import { attemptsExhausted, backoffMs } from './backoff'
import { transitiveDependents } from './cascade'
import type { QueueDB } from './db'
import type { QueuedMutation } from './types'

// Drenagem da fila offline (offline-pwa 4.3 + 5.1/5.2/5.3 / D7-3/D7-4/D7-5). Laço
// sequencial por `seq` restrito pelo grafo, UMA requisição em voo. A classe da
// resposta decide o destino do item; um permanente/conflito bloqueia o fechamento
// transitivo dos dependentes sem travar os independentes.

export interface SendResult {
  ok: boolean
  status: number
  networkError?: boolean
  body?: unknown // corpo do servidor (usado no 409 lock_version)
  resolvedUuids?: string[] // uuids que o servidor confirmou nesta resposta (D1/4.2)
}

export interface DrainDeps {
  probe: () => Promise<boolean>
  send: (m: QueuedMutation) => Promise<SendResult>
  db?: QueueDB
  onChange?: () => void
  now?: () => number
  random?: () => number
  onAuthPause?: () => void // 401: dispara refresh/login (D4)
}

export interface DrainOutcome {
  skipped: boolean
  sent: number
  paused: boolean
}

let draining = false
// Pausa global da fila (401): nenhum item drena até `resumeQueue()`. Não consome
// tentativa do item em voo — token expirado não queima as 8 tentativas.
let paused = false

export function pauseQueue(): void {
  paused = true
}
export function resumeQueue(): void {
  paused = false
}
export function isQueuePaused(): boolean {
  return paused
}

// Marca um item como falho e bloqueia o fechamento transitivo dos dependentes
// (D7-5): eles ficam `blocked` (órfãos), não `failed`. Os independentes seguem.
async function failAndCascade(
  item: QueuedMutation,
  failure: { failure_class: QueuedMutation['failure_class']; last_error: string; server_state?: unknown },
  db?: QueueDB,
): Promise<void> {
  await transition(
    item.id,
    'failed',
    { failure_class: failure.failure_class, last_error: failure.last_error, server_state: failure.server_state },
    db,
  )
  const all = await listMutations(undefined, db)
  const orphans = transitiveDependents(all, [item.resource_uuid])
  for (const id of orphans) {
    const dep = all.find((m) => m.id === id)
    if (dep && (dep.state === 'enqueued' || dep.state === 'inflight')) {
      await transition(id, 'blocked', { last_error: 'bloqueado: depende de um item que falhou' }, db)
    }
  }
}

export async function drainQueue(deps: DrainDeps): Promise<DrainOutcome> {
  const now = deps.now ?? (() => Date.now())
  const random = deps.random ?? Math.random

  if (draining) return { skipped: true, sent: 0, paused }
  if (paused) return { skipped: true, sent: 0, paused: true }
  draining = true
  try {
    if (!(await deps.probe())) return { skipped: true, sent: 0, paused }

    let sent = 0
    for (;;) {
      if (paused) break
      const resolved = await getResolvedUuids(deps.db)
      const items = await listMutations(undefined, deps.db)
      // Elegível pelo grafo E com o backoff já vencido (next_attempt_at no passado).
      const ready = items.filter((m) => m.next_attempt_at == null || m.next_attempt_at <= now())
      const next = nextEligible(ready, resolved)
      if (!next) break

      await transition(next.id, 'inflight', {}, deps.db)
      deps.onChange?.()

      let res: SendResult
      try {
        res = await deps.send(next)
      } catch {
        res = { ok: false, status: 0, networkError: true }
      }

      const decision = classifyResponse({ status: res.status, networkError: res.networkError, method: next.method })

      if (decision.kind === 'success') {
        await transition(next.id, 'done', { last_error: null }, deps.db)
        await markResolved(next.resource_uuid, { db: deps.db })
        for (const uuid of res.resolvedUuids ?? []) await markResolved(uuid, { db: deps.db })
        sent += 1
        deps.onChange?.()
        continue
      }

      if (decision.kind === 'auth') {
        // Pausa a fila SEM consumir tentativa; devolve o item a enfileirado.
        paused = true
        await transition(next.id, 'enqueued', {}, deps.db)
        deps.onAuthPause?.()
        deps.onChange?.()
        break
      }

      if (decision.kind === 'retry') {
        const attempts = next.attempts + (decision.countsAttempt ? 1 : 0)
        if (decision.countsAttempt && attemptsExhausted(attempts)) {
          await failAndCascade(
            next,
            { failure_class: 'esgotado', last_error: `esgotado após ${attempts} tentativas (HTTP ${res.status})` },
            deps.db,
          )
          deps.onChange?.()
          continue // independentes seguem drenando
        }
        await transition(
          next.id,
          'enqueued',
          { attempts, next_attempt_at: now() + backoffMs(attempts, random), last_error: `HTTP ${res.status}` },
          deps.db,
        )
        deps.onChange?.()
        // O item volta com backoff futuro; o `ready` o exclui até vencer. Segue o laço.
        continue
      }

      // conflict (409) | permanent (403/404/422)
      await failAndCascade(
        next,
        {
          failure_class: decision.kind === 'conflict' ? 'conflito' : 'permanente',
          last_error: `HTTP ${res.status}`,
          server_state: decision.kind === 'conflict' ? res.body : undefined,
        },
        deps.db,
      )
      deps.onChange?.()
      // NÃO reenvia automaticamente (409 lock_version nunca casaria); segue os independentes.
    }
    return { skipped: false, sent, paused }
  } finally {
    draining = false
  }
}

// Semeia `resolved_uuids` a partir de uuids lidos do servidor (D1/4.2).
export async function seedResolvedFromServer(uuids: Iterable<string>, db?: QueueDB): Promise<void> {
  for (const uuid of uuids) await markResolved(uuid, { db })
}

// Só para testes.
export function _resetDrainGuard(): void {
  draining = false
  paused = false
}
