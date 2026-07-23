import { describe, it, expect, vi } from 'vitest'
import { keysForEvent, eventMap, type RealtimeEnvelope, type EventType } from '../eventMap'

const W = 'w1'
function env(type: string, scope: RealtimeEnvelope['scope'] = {}, entity: RealtimeEnvelope['entity'] = null): RealtimeEnvelope {
  return { v: 1, seq: 1, workspace_id: W, type, entity, scope, actor_person_id: null, origin_id: null, at: '2026-07-23T00:00:00Z' }
}
const asStr = (keys: readonly unknown[][]) => keys.map((k) => JSON.stringify(k))
const has = (keys: readonly unknown[][], target: unknown[]) => asStr(keys).includes(JSON.stringify(target))

describe('eventMap (5.3 / D6.3)', () => {
  it('task_advance.created invalida a trilha, my-tasks e a cadeia de rollup inteira', () => {
    const keys = keysForEvent(W, env('task_advance.created', { project_id: 'p', cell_id: 'c', robot_id: 'r' }, { kind: 'task', id: 't' }))
    expect(has(keys, ['ws', W, 'robot', 'r'])).toBe(true) // prefixo cobre …/'tasks'
    expect(has(keys, ['ws', W, 'cell', 'c'])).toBe(true) // prefixo cobre …/'robots'
    expect(has(keys, ['ws', W, 'project', 'p'])).toBe(true) // prefixo cobre …/'cells'
    expect(has(keys, ['ws', W, 'overview'])).toBe(true)
    expect(has(keys, ['ws', W, 'my-tasks'])).toBe(true)
    expect(has(keys, ['ws', W, 'task', 't', 'advances'])).toBe(true)
  })

  it('robot.batch_created invalida célula/projeto/overview — e NÃO um robô específico', () => {
    const keys = keysForEvent(W, env('robot.batch_created', { project_id: 'p', cell_id: 'c' }))
    expect(has(keys, ['ws', W, 'cell', 'c'])).toBe(true)
    expect(has(keys, ['ws', W, 'project', 'p'])).toBe(true)
    expect(has(keys, ['ws', W, 'overview'])).toBe(true)
    expect(keys.some((k) => k[2] === 'robot')).toBe(false)
  })

  it('membership.role_changed invalida members/invitations/people, sem rollup', () => {
    const keys = keysForEvent(W, env('membership.role_changed'))
    expect(has(keys, ['ws', W, 'members'])).toBe(true)
    expect(has(keys, ['ws', W, 'people'])).toBe(true)
    expect(has(keys, ['ws', W, 'overview'])).toBe(false)
  })

  it('workspace.reset invalida a subárvore inteira do workspace', () => {
    expect(keysForEvent(W, env('workspace.reset'))).toEqual([['ws', W]])
  })

  it('tipo desconhecido invalida ["ws",w] inteiro e AVISA (nunca engole)', () => {
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => {})
    const keys = keysForEvent(W, env('gizmo.created'))
    expect(keys).toEqual([['ws', W]])
    expect(warn).toHaveBeenCalledWith(expect.stringContaining('gizmo.created'))
    warn.mockRestore()
  })

  it('o mapa é exaustivo sobre a união fechada (toda entrada é função)', () => {
    const types: EventType[] = [
      'project.created', 'cell.updated', 'robot.deleted', 'robot.batch_created',
      'task.assigned', 'task_advance.created', 'membership.revoked', 'notification.created', 'workspace.updated',
    ]
    for (const t of types) expect(typeof eventMap[t]).toBe('function')
  })
})
