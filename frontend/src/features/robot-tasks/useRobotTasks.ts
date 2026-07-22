import { useQuery } from '@tanstack/react-query'
import { robotTasksApi } from '../../lib/api/endpoints'
import { catalogKeys } from '../../lib/api/catalogKeys'
import { qk } from '../../lib/query/keys'
import { useWorkspaceStore } from '../../store/workspaceStore'

export type { TaskDTO, RobotHeaderDTO } from '../../lib/api/endpoints'

// robot-task-table 1.3 (§3.5, D-RTT-3/10) — a leitura da tabela. UMA query por robô,
// na chave `catalogKeys.robotTasks` (= `['ws',wsId,'robot',robotId,'tasks']`), a MESMA
// que `<AdvanceControls>` lê/invalida. Nenhuma célula importa `apiClient` (D-RTT-10).
export function useRobotTasks(robotId: string | null) {
  const wsId = useWorkspaceStore((s) => s.currentWorkspaceId)
  return useQuery({
    queryKey: catalogKeys.robotTasks(wsId, robotId ?? '_'),
    queryFn: () => robotTasksApi.listForRobot(robotId as string),
    enabled: Boolean(wsId && robotId),
  })
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
