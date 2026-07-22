import { useMutation, useQueryClient } from '@tanstack/react-query'
import { robotTasksApi, hierarchyApi } from '../../lib/api/endpoints'
import { catalogKeys } from '../../lib/api/catalogKeys'
import { qk } from '../../lib/query/keys'
import { newId } from '../../lib/ids'
import { useWorkspaceStore } from '../../store/workspaceStore'

// robot-task-table 4.2/4.3 (§2.6, §3.5, D-RTT-10) — as mutações avulsas da tabela
// (criar/editar/excluir tarefa e sincronizar tarefas-base). TODAS invalidam o
// MESMO trio da G2 para o cabeçalho ponderado e os anéis da hierarquia
// recalcularem sem F5: `robotTasks` (a linha), `qk.robot` EXATO (o % do topo desta
// tela) e `qk.projects` (os anéis das telas de cima).

function useRobotInvalidation(robotId: string) {
  const wsId = useWorkspaceStore((s) => s.currentWorkspaceId)
  const queryClient = useQueryClient()
  return () => {
    void queryClient.invalidateQueries({ queryKey: catalogKeys.robotTasks(wsId, robotId) })
    void queryClient.invalidateQueries({ queryKey: qk.robot(wsId ?? '_', robotId), exact: true })
    void queryClient.invalidateQueries({ queryKey: qk.projects(wsId ?? '_') })
  }
}

export function useCreateTask(robotId: string) {
  const invalidate = useRobotInvalidation(robotId)
  return useMutation({
    mutationFn: (data: { cat: string; desc: string }) =>
      robotTasksApi.create(robotId, { id: newId(), cat: data.cat, desc: data.desc }),
    onSuccess: invalidate,
  })
}

export function useUpdateTaskDesc(robotId: string) {
  const invalidate = useRobotInvalidation(robotId)
  return useMutation({
    mutationFn: ({ taskId, desc, lockVersion }: { taskId: string; desc: string; lockVersion: number }) =>
      robotTasksApi.update(taskId, { desc, lock_version: lockVersion }),
    onSuccess: invalidate,
  })
}

export function useDeleteTask(robotId: string) {
  const invalidate = useRobotInvalidation(robotId)
  return useMutation({
    mutationFn: (taskId: string) => robotTasksApi.remove(taskId),
    onSuccess: invalidate,
  })
}

// §2.6 — a sincronização devolve `addedCount`. O componente reseta o filtro para
// "Todos" (as linhas novas aparecem mesmo se o filtro estava em "Concluídos").
export function useSyncTemplates(robotId: string) {
  const invalidate = useRobotInvalidation(robotId)
  return useMutation({
    mutationFn: () => hierarchyApi.syncRobotTaskTemplates(robotId),
    onSuccess: invalidate,
  })
}
