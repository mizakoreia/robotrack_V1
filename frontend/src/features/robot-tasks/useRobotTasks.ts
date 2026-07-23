import { useMemo } from 'react'
import { useQuery } from '@tanstack/react-query'
import { robotTasksApi, type TaskDTO } from '../../lib/api/endpoints'
import { catalogKeys } from '../../lib/api/catalogKeys'
import { qk } from '../../lib/query/keys'
import { useWorkspaceStore } from '../../store/workspaceStore'
import { useOfflineQueueStore } from '../../store/offlineQueueStore'
import { overlayRobotTasks } from '../../lib/offline/overlay'

export type { TaskDTO, RobotHeaderDTO } from '../../lib/api/endpoints'

// robot-task-table 1.3 (§3.5, D-RTT-3/10) — a leitura da tabela. UMA query por robô,
// na chave `catalogKeys.robotTasks` (= `['ws',wsId,'robot',robotId,'tasks']`), a MESMA
// que `<AdvanceControls>` lê/invalida. Nenhuma célula importa `apiClient` (D-RTT-10).
//
// offline-pwa 7.2 (D7-7) — a sobreposição otimista é DERIVADA DA FILA, aplicada na
// leitura (não por `setQueryData`). Precedência: para uma tarefa com avanço
// pendente, o valor otimista vence o do servidor, INCLUSIVE dado recém-chegado por
// evento ao vivo (o refetch reaplica o overlay → sem flicker 60→50). Quando o item
// sai da fila, o servidor volta a mandar. Reativo à fila (Zustand) e ao servidor.
export function useRobotTasks(robotId: string | null) {
  const wsId = useWorkspaceStore((s) => s.currentWorkspaceId)
  const pending = useOfflineQueueStore((s) => s.mutations)
  const query = useQuery({
    queryKey: catalogKeys.robotTasks(wsId, robotId ?? '_'),
    queryFn: () => robotTasksApi.listForRobot(robotId as string),
    enabled: Boolean(wsId && robotId),
  })

  const data = useMemo(
    () => (query.data ? overlayRobotTasks<TaskDTO>(query.data, pending, robotId ?? undefined) : query.data),
    [query.data, pending, robotId],
  )

  return { ...query, data }
}

// Cabeçalho do robô (nome, Aplicação, % ponderado). Key própria de meta do robô.
export function useRobotHeader(robotId: string | null) {
  const wsId = useWorkspaceStore((s) => s.currentWorkspaceId)
  return useQuery({
    queryKey: qk.robot(wsId ?? '_', robotId ?? '_'),
    queryFn: () => robotTasksApi.getRobot(robotId as string),
    enabled: Boolean(wsId && robotId),
  })
}
