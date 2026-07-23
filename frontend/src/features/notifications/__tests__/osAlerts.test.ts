import { describe, it, expect, vi } from 'vitest'
import { processNotifications, initialAlertState, type AlertDeps, type AlertState } from '../osAlerts'
import type { NotificationDTO } from '@/lib/api/endpoints'

// in-app-notifications 7.5 (D-N8) — os quatro cenários críticos da marca d'água.
// O primeiro (reload com não lidas antigas → 0 alertas) é o modo de falha explícito
// desta capacidade: sem este teste, ele volta em silêncio.

const n = (id: string, recorded_at: string, read = false): NotificationDTO => ({
  id,
  type: 'progress',
  msg: `msg ${id}`,
  author_name_snapshot: 'Bruno',
  recorded_at,
  created_at: recorded_at,
  ts_local: '',
  read,
  read_at: null,
  ctx: { project_id: null, cell_id: null, robot_id: 'r', task_id: 't' },
})

function deps(over: Partial<AlertDeps> = {}): { deps: AlertDeps; fire: ReturnType<typeof vi.fn> } {
  const fire = vi.fn()
  return {
    fire,
    deps: {
      permission: over.permission ?? (() => 'granted'),
      visible: over.visible ?? (() => false), // aba oculta = pode disparar
      fire: over.fire ?? fire,
    },
  }
}

describe('marca d\'água do alerta do SO (7.5)', () => {
  it('CENÁRIO 1: reload com 10 não lidas antigas → 0 alertas (só inicializa)', () => {
    const list = Array.from({ length: 10 }, (_, i) => n(`old${i}`, `2026-07-22T10:0${i}:00Z`))
    const { deps: d, fire } = deps()
    const { state, fired } = processNotifications(list, initialAlertState(), d)
    expect(fired).toBe(0)
    expect(fire).not.toHaveBeenCalled()
    expect(state.initialized).toBe(true)
  })

  it('CENÁRIO 2: item novo pós-carga → 1 alerta', () => {
    const initial = Array.from({ length: 10 }, (_, i) => n(`old${i}`, `2026-07-22T10:0${i}:00Z`))
    const { deps: d, fire } = deps()
    let { state } = processNotifications(initial, initialAlertState(), d)

    // chega um item mais novo que a marca
    const novo = n('novo', '2026-07-23T14:03:00Z')
    ;({ state } = processNotifications([novo, ...initial], state, d))
    expect(fire).toHaveBeenCalledTimes(1)
    expect(fire).toHaveBeenCalledWith(expect.objectContaining({ id: 'novo' }))
  })

  it('CENÁRIO 3: permissão negada → 0 construções', () => {
    const { deps: d, fire } = deps({ permission: () => 'denied' })
    let { state } = processNotifications([n('a', '2026-07-22T10:00:00Z')], initialAlertState(), d)
    ;({ state } = processNotifications([n('b', '2026-07-23T14:03:00Z')], state, d))
    expect(fire).not.toHaveBeenCalled()
    void state
  })

  it('CENÁRIO 4: 2 dias offline com 40 pendentes → 0 alertas (só inicializa)', () => {
    const list = Array.from({ length: 40 }, (_, i) => n(`p${i}`, `2026-07-21T${String(i % 24).padStart(2, '0')}:00:00Z`))
    const { deps: d, fire } = deps()
    const { fired } = processNotifications(list, initialAlertState(), d)
    expect(fired).toBe(0)
    expect(fire).not.toHaveBeenCalled()
  })
})

describe('supressão e dedup (7.3)', () => {
  function afterInit(d: AlertDeps): AlertState {
    return processNotifications([n('seed', '2026-07-22T00:00:00Z')], initialAlertState(), d).state
  }

  it('aba VISÍVEL → suprime (0 alertas), mas marca como visto', () => {
    const { deps: d, fire } = deps({ visible: () => true })
    const state = afterInit(d)
    const { fired } = processNotifications([n('x', '2026-07-23T14:03:00Z')], state, d)
    expect(fired).toBe(0)
    expect(fire).not.toHaveBeenCalled()
  })

  it('mesma notificação por evento E por refetch → 1 alerta (dedup por id)', () => {
    const { deps: d, fire } = deps()
    let state = afterInit(d)
    const x = n('x', '2026-07-23T14:03:00Z')
    ;({ state } = processNotifications([x], state, d)) // via evento
    ;({ state } = processNotifications([x], state, d)) // via refetch
    expect(fire).toHaveBeenCalledTimes(1)
  })
})
