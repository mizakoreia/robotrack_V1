import { describe, it, expect } from 'vitest'
import { overlayRobotTasks, overlayRobots, deriveStatus } from '../overlay'
import { mergeSaveState } from '../../../store/persistenceStore'
import type { QueuedMutation } from '../types'

// offline-pwa 7.1/7.3 — a sobreposição pura e a fusão do indicador.

const mut = (over: Partial<QueuedMutation>): QueuedMutation =>
  ({
    id: over.id!,
    seq: over.seq ?? 1,
    kind: over.kind ?? 'advance.create',
    resource_uuid: over.resource_uuid ?? over.id!,
    workspace_id: 'W1',
    method: 'POST',
    url: '/x',
    body: over.body ?? {},
    depends_on: over.depends_on ?? [],
    recorded_at: '',
    state: over.state ?? 'enqueued',
    attempts: 0,
    next_attempt_at: null,
    last_error: null,
  }) as QueuedMutation

describe('overlayRobotTasks — avanços (7.1)', () => {
  it('avanço pendente 50→60 sobre server 50 produz 60, status Em Andamento', () => {
    const server = [{ id: 't1', progress: 50, status: 'Pendente' }]
    const pending = [mut({ id: 'a1', kind: 'advance.create', body: { task_id: 't1', progress: 60 } })]
    const [t] = overlayRobotTasks(server, pending)
    expect(t.progress).toBe(60)
    expect(t.status).toBe('Em Andamento')
  })

  it('último avanço pendente da mesma tarefa vence (ordem seq)', () => {
    const server = [{ id: 't1', progress: 50 }]
    const pending = [
      mut({ id: 'a1', seq: 1, body: { task_id: 't1', progress: 60 } }),
      mut({ id: 'a2', seq: 2, body: { task_id: 't1', progress: 70 } }),
    ]
    expect(overlayRobotTasks(server, pending)[0].progress).toBe(70)
  })

  it('item done/failed NÃO sobrepõe (só pendentes)', () => {
    const server = [{ id: 't1', progress: 50 }]
    const pending = [mut({ id: 'a1', state: 'done', body: { task_id: 't1', progress: 60 } })]
    expect(overlayRobotTasks(server, pending)[0].progress).toBe(50)
  })

  it('tarefa criada offline é anexada quando ausente do servidor', () => {
    const server: Array<{ id: string; progress?: number }> = []
    const pending = [mut({ id: 'tX', kind: 'task.create', resource_uuid: 'tX', body: { name: 'Nova', robot_id: 'r1' } })]
    const out = overlayRobotTasks(server, pending, 'r1')
    expect(out.map((t) => t.id)).toEqual(['tX'])
  })
})

describe('overlayRobots (7.1)', () => {
  it('robô criado offline é anexado à célula', () => {
    const server = [{ id: 'r1', name: 'R1' }]
    const pending = [mut({ id: 'rX', kind: 'robot.create', resource_uuid: 'rX', body: { name: 'Novo', cell_id: 'c1' } })]
    expect(overlayRobots(server, pending, 'c1').map((r) => r.id)).toEqual(['r1', 'rX'])
  })
})

describe('deriveStatus', () => {
  it('0→Pendente, meio→Em Andamento, 100→Concluído', () => {
    expect(deriveStatus(0)).toBe('Pendente')
    expect(deriveStatus(60)).toBe('Em Andamento')
    expect(deriveStatus(100)).toBe('Concluído')
  })
})

describe('mergeSaveState (7.3)', () => {
  it('sem fila → estado base', () => {
    expect(mergeSaveState('saved', { pending: 0, blocked: 0 })).toBe('saved')
  })
  it('pendente vence salvando/salvo', () => {
    expect(mergeSaveState('saved', { pending: 2, blocked: 0 })).toBe('pendente')
    expect(mergeSaveState('saving', { pending: 1, blocked: 0 })).toBe('pendente')
  })
  it('bloqueado vence tudo', () => {
    expect(mergeSaveState('saved', { pending: 3, blocked: 1 })).toBe('bloqueado')
    expect(mergeSaveState('error', { pending: 0, blocked: 2 })).toBe('bloqueado')
  })
  it('erro vence pendente (nunca some um erro por causa da fila)', () => {
    expect(mergeSaveState('error', { pending: 5, blocked: 0 })).toBe('error')
  })
})
