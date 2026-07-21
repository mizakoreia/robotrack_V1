import { useMutation, useQueryClient } from '@tanstack/react-query'
import { hierarchyApi, type BatchRobotInput } from '../../lib/api/endpoints'
import { hierarchyKeys } from '../../lib/api/hierarchyKeys'
import { useWorkspaceStore } from '../../store/workspaceStore'

// robot-tasks 5.6 (§2.5, D9) — a mutation da criação em lote. Ao concluir,
// invalida os robôs da célula e a árvore de projetos, para a hierarquia mostrar
// a leva nova sem reload.
export function useBatchCreateRobots(cellId: string) {
  const wsId = useWorkspaceStore((s) => s.currentWorkspaceId)
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: (data: { application: string; robots: BatchRobotInput[] }) =>
      hierarchyApi.batchCreateRobots(cellId, data),
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: hierarchyKeys.robots(wsId, cellId) })
      void queryClient.invalidateQueries({ queryKey: hierarchyKeys.projects(wsId) })
    },
  })
}

// Clamp de UX de leva (§2.5): 1–50. Digitar 99 vira 50; 0 vira 1. É o MESMO
// clamp do servidor — a UI o repete por conveniência, não por segurança.
export function clampQuantity(value: number): number {
  if (!Number.isFinite(value)) return 1
  return Math.max(1, Math.min(50, Math.floor(value)))
}
