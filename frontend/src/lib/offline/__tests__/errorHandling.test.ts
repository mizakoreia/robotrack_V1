import 'fake-indexeddb/auto'
import { describe, it, expect, beforeEach, vi } from 'vitest'
import { IDBFactory } from 'fake-indexeddb'
import { _resetQueueDbSingleton } from '../db'
import { enqueueMutation, listMutations } from '../queue'
import { drainQueue, isQueuePaused, resumeQueue, _resetDrainGuard, type SendResult } from '../drain'
import { discardWithClosure, closureCount, fixAndResend } from '../reconcile'
import { MAX_RETRY_ATTEMPTS } from '../backoff'
import type { EnqueueInput, QueuedMutation } from '../types'

// offline-pwa 5.1-5.5 — erro, backoff, cascata, pausa por auth, reconciliação e
// replay duplicado, exercitados pela máquina de drenagem real.

function input(over: Partial<EnqueueInput>): EnqueueInput {
  return {
    id: over.id!,
    kind: over.kind ?? 'robot.create',
    resource_uuid: over.resource_uuid ?? over.id!,
    workspace_id: over.workspace_id ?? 'W1',
    method: over.method ?? 'POST',
    url: over.url ?? '/api/v1/robots',
    body: over.body ?? {},
    depends_on: over.depends_on ?? [],
    recorded_at: over.recorded_at,
  }
}

const okProbe = async () => true
const byId = (items: QueuedMutation[], id: string) => items.find((m) => m.id === id)!

beforeEach(() => {
  globalThis.indexedDB = new IDBFactory()
  _resetQueueDbSingleton()
  _resetDrainGuard()
})

describe('retryable com backoff (5.2)', () => {
  it('500 devolve a enqueued com attempts++ e backoff futuro', async () => {
    await enqueueMutation(input({ id: 'R' }))
    const send = vi.fn(async (): Promise<SendResult> => ({ ok: false, status: 500 }))
    await drainQueue({ probe: okProbe, send, now: () => 1000, random: () => 0.5 })

    const r = byId(await listMutations('W1'), 'R')
    expect(r.state).toBe('enqueued')
    expect(r.attempts).toBe(1)
    expect(r.next_attempt_at).toBe(1000 + 2000) // 2^1×1s, jitter zero
    expect(send).toHaveBeenCalledTimes(1) // backoff impede reenvio imediato
  })

  it('erro de rede NÃO conta tentativa (só backoff)', async () => {
    await enqueueMutation(input({ id: 'R' }))
    const send = vi.fn(async (): Promise<SendResult> => ({ ok: false, status: 0, networkError: true }))
    await drainQueue({ probe: okProbe, send, now: () => 0, random: () => 0.5 })
    expect(byId(await listMutations('W1'), 'R').attempts).toBe(0)
  })

  it('esgotar 8 tentativas → failed "esgotado"', async () => {
    const m = await enqueueMutation(input({ id: 'R' }))
    // Simula 7 tentativas já consumidas; a 8ª esgota.
    const { transition } = await import('../queue')
    await transition('R', 'enqueued', { attempts: MAX_RETRY_ATTEMPTS - 1 })
    void m
    const send = vi.fn(async (): Promise<SendResult> => ({ ok: false, status: 500 }))
    await drainQueue({ probe: okProbe, send, now: () => 0, random: () => 0.5 })

    const r = byId(await listMutations('W1'), 'R')
    expect(r.state).toBe('failed')
    expect(r.failure_class).toBe('esgotado')
  })
})

describe('cascata de bloqueio (5.3)', () => {
  it('permanente bloqueia o fechamento; independentes chegam a done', async () => {
    // R falha 422; T(dep R) e A(dep T) bloqueiam; P independente drena.
    await enqueueMutation(input({ id: 'R', resource_uuid: 'R' }))
    await enqueueMutation(input({ id: 'T', resource_uuid: 'T', kind: 'task.create', depends_on: ['R'] }))
    await enqueueMutation(input({ id: 'A', resource_uuid: 'A', kind: 'advance.create', depends_on: ['T'] }))
    await enqueueMutation(input({ id: 'P', resource_uuid: 'P', kind: 'project.rename', depends_on: [] }))

    const send = vi.fn(async (m: QueuedMutation): Promise<SendResult> => {
      if (m.id === 'R') return { ok: false, status: 422 }
      return { ok: true, status: 200 }
    })
    await drainQueue({ probe: okProbe, send, now: () => 0 })

    const items = await listMutations('W1')
    expect(byId(items, 'R').state).toBe('failed')
    expect(byId(items, 'T').state).toBe('blocked')
    expect(byId(items, 'A').state).toBe('blocked')
    expect(byId(items, 'P').state).toBe('done') // independente não trava
  })
})

describe('401 pausa a fila (5.2)', () => {
  it('pausa sem consumir tentativa e devolve o item a enqueued', async () => {
    await enqueueMutation(input({ id: 'R' }))
    const onAuthPause = vi.fn()
    const send = vi.fn(async (): Promise<SendResult> => ({ ok: false, status: 401 }))
    const out = await drainQueue({ probe: okProbe, send, onAuthPause })

    expect(out.paused).toBe(true)
    expect(isQueuePaused()).toBe(true)
    expect(onAuthPause).toHaveBeenCalled()
    const r = byId(await listMutations('W1'), 'R')
    expect(r.state).toBe('enqueued')
    expect(r.attempts).toBe(0) // token expirado não queima tentativa

    // Enquanto pausada, drenar não faz nada.
    const send2 = vi.fn()
    const out2 = await drainQueue({ probe: okProbe, send: send2 })
    expect(send2).not.toHaveBeenCalled()
    expect(out2.skipped).toBe(true)
    resumeQueue()
  })
})

describe('409 lock_version → reconciliação, sem reenvio (5.4)', () => {
  it('vira failed "conflito" com o estado do servidor no corpo', async () => {
    await enqueueMutation(input({ id: 'A', kind: 'advance.create', method: 'PATCH' }))
    const serverState = { progress: 50, lock_version: 7 }
    const send = vi.fn(async (): Promise<SendResult> => ({ ok: false, status: 409, body: serverState }))
    await drainQueue({ probe: okProbe, send })

    const r = byId(await listMutations('W1'), 'A')
    expect(r.state).toBe('failed')
    expect(r.failure_class).toBe('conflito')
    expect(r.server_state).toEqual(serverState)
    expect(send).toHaveBeenCalledTimes(1) // nunca reenvia em laço contra o lock
  })
})

describe('reconciliação (5.4)', () => {
  it('Descartar N remove o item falho + o fechamento transitivo', async () => {
    await enqueueMutation(input({ id: 'R', resource_uuid: 'R' }))
    await enqueueMutation(input({ id: 'T', resource_uuid: 'T', depends_on: ['R'] }))
    await enqueueMutation(input({ id: 'A', resource_uuid: 'A', depends_on: ['T'] }))
    const send = vi.fn(async (m: QueuedMutation): Promise<SendResult> => ({ ok: m.id !== 'R', status: m.id === 'R' ? 422 : 200 }))
    await drainQueue({ probe: okProbe, send })

    expect(await closureCount('R')).toBe(3) // "Descartar 3 alterações"
    const removed = await discardWithClosure('R')
    expect(removed).toBe(3)
    expect(await listMutations('W1')).toHaveLength(0)
  })

  it('Corrigir e reenviar destrava os órfãos bloqueados', async () => {
    await enqueueMutation(input({ id: 'R', resource_uuid: 'R', body: { name: '' } }))
    await enqueueMutation(input({ id: 'T', resource_uuid: 'T', depends_on: ['R'] }))
    const send = vi.fn(async (m: QueuedMutation): Promise<SendResult> => ({ ok: m.id !== 'R', status: m.id === 'R' ? 422 : 200 }))
    await drainQueue({ probe: okProbe, send })

    expect(byId(await listMutations('W1'), 'T').state).toBe('blocked')
    await fixAndResend('R', { name: 'Robô corrigido' })

    const items = await listMutations('W1')
    expect(byId(items, 'R').state).toBe('enqueued')
    expect(byId(items, 'R').body).toEqual({ name: 'Robô corrigido' })
    expect(byId(items, 'T').state).toBe('enqueued') // órfão destravado
  })
})

describe('replay duplicado (5.5 / D7-6)', () => {
  it('o uuid do recurso é a chave de idempotência — reenvio carrega o MESMO uuid', async () => {
    await enqueueMutation(input({ id: 'A', kind: 'advance.create', resource_uuid: 'A', body: { advance_uuid: 'A', delta: 10 } }))

    const seen: string[] = []
    let first = true
    const send = vi.fn(async (m: QueuedMutation): Promise<SendResult> => {
      seen.push((m.body as { advance_uuid: string }).advance_uuid)
      if (first) {
        first = false
        return { ok: false, status: 0, networkError: true } // resposta perdida após o servidor processar
      }
      return { ok: true, status: 200 } // servidor idempotente responde 200 no replay
    })

    await drainQueue({ probe: okProbe, send, now: () => 0 }) // 1ª: rede cai, volta a enqueued (backoff vencido pois next=0)
    await drainQueue({ probe: okProbe, send, now: () => 10_000 }) // 2ª: reenvia com o mesmo uuid

    expect(seen).toEqual(['A', 'A']) // mesma chave → o servidor produz UMA linha, progresso 10 não 20
    expect(byId(await listMutations('W1'), 'A').state).toBe('done')
  })
})
