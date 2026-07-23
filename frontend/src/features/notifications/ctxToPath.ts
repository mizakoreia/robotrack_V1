import type { NotificationDTO } from '@/lib/api/endpoints'

// in-app-notifications 6.3 — do `ctx` da notificação para a rota do robô, com a
// tarefa destacada (`?tarefa=`). Se `robot_id` for nulo (robô excluído ou ctx
// incompleto), devolve null — o chamador mantém a pessoa no centro com um aviso,
// em vez de navegar para uma rota inválida (§2.7).
export function ctxToPath(notification: NotificationDTO): string | null {
  const robotId = notification.ctx.robot_id
  if (!robotId) return null

  const taskId = notification.ctx.task_id
  const query = taskId ? `?tarefa=${encodeURIComponent(taskId)}` : ''
  return `/robo/${encodeURIComponent(robotId)}${query}`
}
