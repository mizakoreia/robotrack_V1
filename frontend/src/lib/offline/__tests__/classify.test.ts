import { describe, it, expect } from 'vitest'
import { classifyResponse, type Decision } from '../classify'
import { backoffMs, attemptsExhausted, MAX_RETRY_ATTEMPTS } from '../backoff'
import { transitiveDependents, closureFrom } from '../cascade'
import type { MutationMethod, QueuedMutation } from '../types'

// offline-pwa 5.5 — teste de TABELA cobrindo cada linha de D7-5.

describe('classifyResponse (5.1 / matriz D7-5)', () => {
  const rows: Array<[string, { status: number; networkError?: boolean; method: MutationMethod }, Decision]> = [
    ['erro de rede', { status: 0, networkError: true, method: 'POST' }, { kind: 'retry', countsAttempt: false }],
    ['fetch rejeitado (status 0)', { status: 0, method: 'POST' }, { kind: 'retry', countsAttempt: false }],
    ['408', { status: 408, method: 'POST' }, { kind: 'retry', countsAttempt: true }],
    ['429', { status: 429, method: 'POST' }, { kind: 'retry', countsAttempt: true }],
    ['500', { status: 500, method: 'POST' }, { kind: 'retry', countsAttempt: true }],
    ['502', { status: 502, method: 'POST' }, { kind: 'retry', countsAttempt: true }],
    ['503', { status: 503, method: 'POST' }, { kind: 'retry', countsAttempt: true }],
    ['504', { status: 504, method: 'POST' }, { kind: 'retry', countsAttempt: true }],
    ['401', { status: 401, method: 'POST' }, { kind: 'auth' }],
    ['409 lock_version', { status: 409, method: 'PATCH' }, { kind: 'conflict' }],
    ['403 papel mudou', { status: 403, method: 'POST' }, { kind: 'permanent' }],
    ['404 removido', { status: 404, method: 'POST' }, { kind: 'permanent' }],
    ['422', { status: 422, method: 'POST' }, { kind: 'permanent' }],
    ['200', { status: 200, method: 'POST' }, { kind: 'success' }],
    ['201', { status: 201, method: 'POST' }, { kind: 'success' }],
    ['DELETE 404 = sucesso (D7-6)', { status: 404, method: 'DELETE' }, { kind: 'success' }],
    ['501 desconhecido → permanente (não gira bateria)', { status: 501, method: 'POST' }, { kind: 'permanent' }],
  ]

  for (const [nome, input, esperado] of rows) {
    it(nome, () => {
      expect(classifyResponse(input)).toEqual(esperado)
    })
  }
})

describe('backoff (5.2)', () => {
  it('cresce 2^n×1s até o teto de 5min (jitter zero no meio)', () => {
    const mid = (a: number) => backoffMs(a, () => 0.5)
    expect(mid(0)).toBe(1000)
    expect(mid(1)).toBe(2000)
    expect(mid(3)).toBe(8000)
    expect(mid(20)).toBe(300000) // teto 5min
  })

  it('jitter fica em ±20%', () => {
    expect(backoffMs(3, () => 1)).toBe(9600) // +20%
    expect(backoffMs(3, () => 0)).toBe(6400) // -20%
  })

  it('teto de 8 tentativas retryable', () => {
    expect(attemptsExhausted(MAX_RETRY_ATTEMPTS - 1)).toBe(false)
    expect(attemptsExhausted(MAX_RETRY_ATTEMPTS)).toBe(true)
  })
})

describe('cascata / fechamento transitivo (5.3)', () => {
  const m = (id: string, resource: string, deps: string[]): QueuedMutation =>
    ({ id, resource_uuid: resource, depends_on: deps, state: 'enqueued' }) as QueuedMutation

  it('dependentes diretos e indiretos entram no fechamento', () => {
    // R ← T ← A ; e um P independente.
    const items = [m('R', 'R', []), m('T', 'T', ['R']), m('A', 'A', ['T']), m('P', 'P', [])]
    const orphans = transitiveDependents(items, ['R'])
    expect([...orphans].sort()).toEqual(['A', 'T'])
    expect(orphans.has('P')).toBe(false)
  })

  it('closureFrom conta o item falho + o fechamento (rótulo "Descartar N")', () => {
    const items = [m('R', 'R', []), m('T', 'T', ['R']), m('A', 'A', ['T']), m('P', 'P', [])]
    expect(closureFrom(items, 'R').size).toBe(3) // R + T + A
  })
})
