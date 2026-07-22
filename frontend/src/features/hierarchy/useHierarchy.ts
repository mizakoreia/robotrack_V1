import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import {
  hierarchyApi,
  type CellDTO,
  type ProjectDTO,
  type RobotApplication,
  type RobotDTO,
} from '../../lib/api/endpoints'
import { hierarchyKeys } from '../../lib/api/hierarchyKeys'
import { qk } from '../../lib/query/keys'
import { newId } from '../../lib/ids'
import { useWorkspaceStore } from '../../store/workspaceStore'
import { moveItem, submitReorder, type ReorderOutcome } from '../../lib/api/reorder'

// commissioning-hierarchy 6.3/6.4/6.5 — hooks de leitura e mutação.
//
// A criação é OTIMISTA usando o id gerado no cliente (D1): o card aparece na
// hora com o id DEFINITIVO, então quando a resposta chega ela substitui a mesma
// entrada em vez de duplicar. `onError` restaura o snapshot; `onSettled`
// invalida a chave, que é a mesma que `realtime-collaboration` vai invalidar.
//
// Nenhuma tela aqui: `hierarchy-screens` é outra capacidade.

export function useProjects() {
  const wsId = useWorkspaceStore((s) => s.currentWorkspaceId)

  return useQuery({
    queryKey: hierarchyKeys.projects(wsId),
    queryFn: () => hierarchyApi.listProjects(),
    enabled: Boolean(wsId),
  })
}

export function useCells(projectId: string | null) {
  const wsId = useWorkspaceStore((s) => s.currentWorkspaceId)

  return useQuery({
    queryKey: hierarchyKeys.cells(wsId, projectId ?? ''),
    queryFn: () => hierarchyApi.listCells(projectId as string),
    enabled: Boolean(wsId && projectId),
  })
}

export function useRobots(cellId: string | null) {
  const wsId = useWorkspaceStore((s) => s.currentWorkspaceId)

  return useQuery({
    queryKey: hierarchyKeys.robots(wsId, cellId ?? ''),
    queryFn: () => hierarchyApi.listRobots(cellId as string),
    enabled: Boolean(wsId && cellId),
  })
}

function optimisticProject(id: string, name: string, position: number): ProjectDTO {
  return {
    id,
    name,
    position,
    lock_version: 0,
    updated_at: new Date().toISOString(),
    updated_by_person_id: null,
    progress: { weighted: 0, done: 0, total: 0 },
    cells: [],
  }
}

export function useCreateProject() {
  const wsId = useWorkspaceStore((s) => s.currentWorkspaceId)
  const queryClient = useQueryClient()
  const key = hierarchyKeys.projects(wsId)

  return useMutation({
    mutationFn: ({ name, id }: { name: string; id?: string }) =>
      hierarchyApi.createProject({ id: id ?? newId(), name }),

    onMutate: async ({ name, id }) => {
      await queryClient.cancelQueries({ queryKey: key })
      const anterior = queryClient.getQueryData<ProjectDTO[]>(key) ?? []
      queryClient.setQueryData<ProjectDTO[]>(key, [
        ...anterior,
        optimisticProject(id ?? newId(), name, anterior.length),
      ])
      return { anterior }
    },

    onError: (_erro, _vars, contexto) => {
      if (contexto?.anterior) queryClient.setQueryData(key, contexto.anterior)
    },

    onSettled: () => {
      void queryClient.invalidateQueries({ queryKey: key })
    },
  })
}

export function useRenameProject() {
  const wsId = useWorkspaceStore((s) => s.currentWorkspaceId)
  const queryClient = useQueryClient()
  const key = hierarchyKeys.projects(wsId)

  return useMutation({
    mutationFn: ({ id, name, lockVersion }: { id: string; name: string; lockVersion: number }) =>
      hierarchyApi.updateProject(id, { name, lock_version: lockVersion }),

    onMutate: async ({ id, name }) => {
      await queryClient.cancelQueries({ queryKey: key })
      const anterior = queryClient.getQueryData<ProjectDTO[]>(key) ?? []
      queryClient.setQueryData<ProjectDTO[]>(
        key,
        anterior.map((p) => (p.id === id ? { ...p, name } : p)),
      )
      return { anterior }
    },

    onError: (_erro, _vars, contexto) => {
      if (contexto?.anterior) queryClient.setQueryData(key, contexto.anterior)
    },

    onSettled: () => {
      void queryClient.invalidateQueries({ queryKey: key })
    },
  })
}

export function useDeleteProject() {
  const wsId = useWorkspaceStore((s) => s.currentWorkspaceId)
  const queryClient = useQueryClient()
  const key = hierarchyKeys.projects(wsId)

  return useMutation({
    mutationFn: (id: string) => hierarchyApi.deleteProject(id),

    onMutate: async (id) => {
      await queryClient.cancelQueries({ queryKey: key })
      const anterior = queryClient.getQueryData<ProjectDTO[]>(key) ?? []
      queryClient.setQueryData<ProjectDTO[]>(
        key,
        anterior.filter((p) => p.id !== id),
      )
      return { anterior }
    },

    onError: (_erro, _id, contexto) => {
      if (contexto?.anterior) queryClient.setQueryData(key, contexto.anterior)
    },

    onSettled: () => {
      void queryClient.invalidateQueries({ queryKey: key })
    },
  })
}

export function useCreateCell(projectId: string) {
  const wsId = useWorkspaceStore((s) => s.currentWorkspaceId)
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: ({ name, id }: { name: string; id?: string }) =>
      hierarchyApi.createCell({ id: id ?? newId(), name, project_id: projectId }),
    onSettled: () => {
      void queryClient.invalidateQueries({ queryKey: hierarchyKeys.cells(wsId, projectId) })
      void queryClient.invalidateQueries({ queryKey: hierarchyKeys.projects(wsId) })
      // hierarchy-screens 5.2 — a grade e o hub da tela de Projeto leem o overview.
      if (wsId) void queryClient.invalidateQueries({ queryKey: qk.projectOverview(wsId, projectId) })
    },
  })
}

// hierarchy-screens 5.2 — renomear e excluir célula, ligados ao CRUD de
// commissioning-hierarchy, invalidando o overview do Projeto (a grade e o hub
// atualizam sem recarregar a página).
export function useRenameCell(projectId: string) {
  const wsId = useWorkspaceStore((s) => s.currentWorkspaceId)
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: ({ id, name, lockVersion }: { id: string; name: string; lockVersion: number }) =>
      hierarchyApi.updateCell(id, { name, lock_version: lockVersion }),
    onSettled: () => {
      void queryClient.invalidateQueries({ queryKey: hierarchyKeys.cells(wsId, projectId) })
      if (wsId) void queryClient.invalidateQueries({ queryKey: qk.projectOverview(wsId, projectId) })
    },
  })
}

export function useDeleteCell(projectId: string) {
  const wsId = useWorkspaceStore((s) => s.currentWorkspaceId)
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: (id: string) => hierarchyApi.deleteCell(id),
    onSettled: () => {
      void queryClient.invalidateQueries({ queryKey: hierarchyKeys.cells(wsId, projectId) })
      void queryClient.invalidateQueries({ queryKey: hierarchyKeys.projects(wsId) })
      if (wsId) void queryClient.invalidateQueries({ queryKey: qk.projectOverview(wsId, projectId) })
    },
  })
}

export function useCreateRobot(cellId: string) {
  const wsId = useWorkspaceStore((s) => s.currentWorkspaceId)
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: ({
      name,
      id,
      application,
    }: {
      name: string
      id?: string
      application?: RobotApplication
    }) => hierarchyApi.createRobot({ id: id ?? newId(), name, cell_id: cellId, application }),
    onSettled: () => {
      void queryClient.invalidateQueries({ queryKey: hierarchyKeys.robots(wsId, cellId) })
    },
  })
}

// O drop monta `ordered_ids` COMPLETO (D-H4) — nunca um par (id, position).
// Um 409 significa que a lista mudou por baixo: recarregamos o escopo em vez de
// gravar por cima, que apagaria o irmão novo.
export function useReorder<T extends { id: string }>(options: {
  items: T[]
  queryKey: readonly unknown[]
  scopeId: string
  send: (scopeId: string, orderedIds: string[]) => Promise<unknown[]>
}) {
  const queryClient = useQueryClient()

  return async function onDrop(from: number, to: number): Promise<ReorderOutcome> {
    const anterior = options.items
    const reordenado = moveItem(anterior, from, to)
    if (reordenado === anterior) return { status: 'ok', items: anterior }

    queryClient.setQueryData(options.queryKey, reordenado)

    const resultado = await submitReorder(() =>
      options.send(
        options.scopeId,
        reordenado.map((i) => i.id),
      ),
    )

    if (resultado.status === 'ok') {
      queryClient.setQueryData(options.queryKey, resultado.items)
    } else {
      queryClient.setQueryData(options.queryKey, anterior)
      void queryClient.invalidateQueries({ queryKey: options.queryKey })
    }

    return resultado
  }
}

export type { CellDTO, ProjectDTO, RobotDTO }
