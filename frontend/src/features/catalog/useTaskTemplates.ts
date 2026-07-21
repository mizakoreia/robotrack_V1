import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import {
  taskTemplatesApi,
  hierarchyApi,
  metaApi,
  type TaskTemplateDTO,
  type TaskTemplateWriteInput,
} from '../../lib/api/endpoints'
import { catalogKeys } from '../../lib/api/catalogKeys'
import { useWorkspaceStore } from '../../store/workspaceStore'

// task-catalog 6.2 (§3.9, §2.6, D9) — hooks de leitura e mutação do catálogo.
//
// Sem tela aqui: `workspace-settings` renderiza este CRUD. As mutações
// invalidam `['ws', wsId, 'taskTemplates']` (a mesma chave que
// `realtime-collaboration` vai invalidar). A sincronização retroativa invalida
// a lista de TAREFAS do robô — `['ws', wsId, 'robot', robotId, 'tasks']` —, não
// a do catálogo: quem muda com o sync é a tabela do robô.

export function useTaskTemplates() {
  const wsId = useWorkspaceStore((s) => s.currentWorkspaceId)

  return useQuery({
    queryKey: catalogKeys.taskTemplates(wsId),
    queryFn: () => taskTemplatesApi.list(),
    enabled: Boolean(wsId),
  })
}

// §1.2 — a lista de Aplicações vem do backend (fonte única) e quase nunca muda:
// `staleTime: Infinity`. A chave é global, sem `wsId`.
export function useRobotApplications() {
  return useQuery({
    queryKey: catalogKeys.robotApplications(),
    queryFn: () => metaApi.robotApplications(),
    staleTime: Infinity,
  })
}

export function useCreateTaskTemplate() {
  const wsId = useWorkspaceStore((s) => s.currentWorkspaceId)
  const queryClient = useQueryClient()
  const key = catalogKeys.taskTemplates(wsId)

  return useMutation({
    mutationFn: (data: TaskTemplateWriteInput) => taskTemplatesApi.create(data),
    onSettled: () => {
      void queryClient.invalidateQueries({ queryKey: key })
    },
  })
}

export function useUpdateTaskTemplate() {
  const wsId = useWorkspaceStore((s) => s.currentWorkspaceId)
  const queryClient = useQueryClient()
  const key = catalogKeys.taskTemplates(wsId)

  return useMutation({
    mutationFn: ({ id, data }: { id: string; data: TaskTemplateWriteInput }) =>
      taskTemplatesApi.update(id, data),
    onSettled: () => {
      void queryClient.invalidateQueries({ queryKey: key })
    },
  })
}

export function useDeleteTaskTemplate() {
  const wsId = useWorkspaceStore((s) => s.currentWorkspaceId)
  const queryClient = useQueryClient()
  const key = catalogKeys.taskTemplates(wsId)

  return useMutation({
    mutationFn: (id: string) => taskTemplatesApi.destroy(id),
    onSettled: () => {
      void queryClient.invalidateQueries({ queryKey: key })
    },
  })
}

// §2.6 — sincroniza os templates aplicáveis para um robô existente. Ao terminar,
// invalida a lista de tarefas DAQUELE robô, para a tabela mostrar as novas sem
// reload manual. Depende do backend do G6 (tabela `tasks`).
export function useSyncTaskTemplates() {
  const wsId = useWorkspaceStore((s) => s.currentWorkspaceId)
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: (robotId: string) => hierarchyApi.syncRobotTaskTemplates(robotId),
    onSuccess: (_data, robotId) => {
      void queryClient.invalidateQueries({ queryKey: catalogKeys.robotTasks(wsId, robotId) })
    },
  })
}

export type { TaskTemplateDTO }
