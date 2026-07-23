import { enqueueMutation } from './queue'
import type { QueueDB } from './db'
import type { QueuedMutation } from './types'

// Produtores da fila offline (offline-pwa 8.5 / D8). Traduzem uma ação do usuário
// em um item de fila com `depends_on` correto e `recorded_at` carimbado no
// instante da CONFIRMAÇÃO (não do envio). São o ponto onde os hooks de mutação
// (useRecordAdvance, useHierarchy) passam a enfileirar quando offline — o corpo
// carrega `recorded_at`, e o servidor guarda esse valor do cliente + o próprio
// `created_at` do envio (a trilha mostra 14:03; o `created_at` do servidor é 17:41).

export async function enqueueAdvance(
  args: {
    advanceId: string
    taskId: string
    robotId: string
    workspaceId: string
    progress?: number
    status?: string
    comment?: string
    recordedAt: string // ISO, carimbado na confirmação do modal (D8)
    lockVersion?: number
  },
  opts: { db?: QueueDB } = {},
): Promise<QueuedMutation> {
  return enqueueMutation(
    {
      id: args.advanceId,
      kind: 'advance.create',
      resource_uuid: args.advanceId,
      workspace_id: args.workspaceId,
      method: 'POST',
      url: `/api/v1/tasks/${args.taskId}/advances`,
      // `recorded_at` viaja no corpo: é a honestidade temporal que o servidor persiste.
      body: {
        id: args.advanceId,
        task_id: args.taskId,
        progress: args.progress,
        status: args.status,
        comment: args.comment,
        recorded_at: args.recordedAt,
        lock_version: args.lockVersion,
      },
      // O avanço depende da tarefa: se ela foi criada offline, espera o 2xx dela.
      depends_on: [args.taskId],
      recorded_at: args.recordedAt,
    },
    { db: opts.db },
  )
}

export async function enqueueRobotCreate(
  args: { robotId: string; cellId: string; name: string; application?: string; workspaceId: string; recordedAt?: string },
  opts: { db?: QueueDB } = {},
): Promise<QueuedMutation> {
  return enqueueMutation(
    {
      id: args.robotId,
      kind: 'robot.create',
      resource_uuid: args.robotId,
      workspace_id: args.workspaceId,
      method: 'POST',
      url: '/api/v1/robots',
      body: { id: args.robotId, cell_id: args.cellId, name: args.name, application: args.application },
      depends_on: [args.cellId],
      recorded_at: args.recordedAt,
    },
    { db: opts.db },
  )
}
