import { useQuery } from '@tanstack/react-query'
import { taskAdvancesApi, type TaskAdvanceDTO } from '../../lib/api/endpoints'
import { advanceKeys } from '../../lib/api/advanceKeys'
import { useWorkspaceStore } from '../../store/workspaceStore'

export type { TaskAdvanceDTO } from '../../lib/api/endpoints'

// robot-task-table 5.1 (§3.5, D8) — a trilha completa de uma tarefa para o modal de
// histórico. Chave `advanceKeys.trail` (a MESMA que a mutation de avanço invalida —
// abrir o histórico após registrar mostra a entrada nova). Só busca com o modal
// aberto (`enabled`). O servidor já ordena por `recorded_at DESC, created_at DESC,
// id DESC` — não reordeno no cliente.
export function useTaskTrail(taskId: string, open: boolean) {
  const wsId = useWorkspaceStore((s) => s.currentWorkspaceId)
  return useQuery({
    queryKey: advanceKeys.trail(wsId, taskId),
    queryFn: (): Promise<TaskAdvanceDTO[]> => taskAdvancesApi.list(taskId, { perPage: 100 }),
    enabled: Boolean(wsId && open),
  })
}
