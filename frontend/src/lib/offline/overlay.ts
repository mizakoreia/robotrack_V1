import type { QueuedMutation } from './types'

// Sobreposição otimista DERIVADA DA FILA (offline-pwa 7.1 / D7-7). Função pura:
// `overlay(serverData, pending) → viewData`. Não usa `setQueryData` — é aplicada
// na leitura. Regra de precedência (D7-7): para uma entidade com mutation
// pendente, a sobreposição SEMPRE vence o dado do servidor, inclusive dado
// recém-chegado por evento ao vivo. Quando a mutation sai da fila (done/descartada)
// a sobreposição some — o servidor volta a mandar, sem rollback manual.

const PENDING_STATES = new Set(['enqueued', 'inflight', 'blocked'])
export const isPending = (m: QueuedMutation): boolean => PENDING_STATES.has(m.state)

// Deriva o status a partir do progresso (mesma convenção da tabela de tarefas).
export function deriveStatus(progress: number): string {
  if (progress >= 100) return 'Concluído'
  if (progress > 0) return 'Em Andamento'
  return 'Pendente'
}

interface TaskLike {
  id: string
  progress?: number
  status?: string
}

function bodyOf(m: QueuedMutation): Record<string, unknown> {
  return (m.body ?? {}) as Record<string, unknown>
}
function pick(body: Record<string, unknown>, ...keys: string[]): unknown {
  for (const k of keys) if (body[k] != null) return body[k]
  return undefined
}

// Tarefas de um robô com os avanços pendentes aplicados + tarefas criadas offline
// ainda não no servidor. Último avanço pendente da mesma tarefa vence (ordem seq).
export function overlayRobotTasks<T extends TaskLike>(
  tasks: T[],
  pending: QueuedMutation[],
  robotId?: string,
): T[] {
  const live = pending.filter(isPending)

  // Avanços: progresso/status.
  const byTask = new Map<string, number>()
  for (const m of live.filter((x) => x.kind === 'advance.create').sort((a, b) => a.seq - b.seq)) {
    const body = bodyOf(m)
    const taskId = pick(body, 'task_id', 'taskId') as string | undefined
    const progress = pick(body, 'progress', 'toProgress') as number | undefined
    if (taskId != null && progress != null) byTask.set(taskId, progress)
  }

  let result = tasks.map((t) => {
    const p = byTask.get(t.id)
    return p == null ? t : { ...t, progress: p, status: deriveStatus(p) }
  })

  // Tarefas criadas offline ainda ausentes do servidor.
  const existing = new Set(result.map((t) => t.id))
  for (const m of live.filter((x) => x.kind === 'task.create').sort((a, b) => a.seq - b.seq)) {
    const body = bodyOf(m)
    const scopeRobot = pick(body, 'robot_id', 'robotId') as string | undefined
    if (robotId != null && scopeRobot != null && scopeRobot !== robotId) continue
    if (existing.has(m.resource_uuid)) continue
    result = [
      ...result,
      { id: m.resource_uuid, name: pick(body, 'name'), progress: 0, status: 'Pendente' } as unknown as T,
    ]
    existing.add(m.resource_uuid)
  }

  return result
}

interface RobotLike {
  id: string
  name?: string
}

// Robôs de uma célula com os criados offline anexados (ainda não no servidor).
export function overlayRobots<T extends RobotLike>(robots: T[], pending: QueuedMutation[], cellId?: string): T[] {
  const existing = new Set(robots.map((r) => r.id))
  let result = robots
  for (const m of pending.filter((x) => isPending(x) && x.kind === 'robot.create').sort((a, b) => a.seq - b.seq)) {
    const body = bodyOf(m)
    const scopeCell = pick(body, 'cell_id', 'cellId') as string | undefined
    if (cellId != null && scopeCell != null && scopeCell !== cellId) continue
    if (existing.has(m.resource_uuid)) continue
    result = [...result, { id: m.resource_uuid, name: pick(body, 'name') } as unknown as T]
    existing.add(m.resource_uuid)
  }
  return result
}
