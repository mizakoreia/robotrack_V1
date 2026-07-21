import { useCallback, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import {
  taskAssigneesApi,
  peopleApi,
  membershipsApi,
  type PersonDTO,
} from '../../lib/api/endpoints'
import { catalogKeys } from '../../lib/api/catalogKeys'
import { newId } from '../../lib/ids'
import { useWorkspaceStore } from '../../store/workspaceStore'

// robot-tasks 4.4 (§3.5, §2.7, D9) — a lógica do modal de atribuição.
//
// Sem visual aqui (a tabela e o modal renderizados são de `robot-task-table`):
// isto é o comportamento — a lista de pessoas do workspace, a seleção múltipla,
// o cadastro de pessoa nova (que já sai marcada) e o PUT do conjunto.
//
// A lista de pessoas vem HOJE dos MEMBROS (workspace-tenancy ainda não expõe
// GET /people); pessoas cadastradas no modal entram pelo cache otimista e
// sobrevivem ao fechamento sem reload. O cadastro usa `POST /people`
// (workspace-tenancy — dependência declarada).

export const peopleKey = (wsId: string | null) => ['ws', wsId, 'people'] as const

export function useWorkspacePeople() {
  const wsId = useWorkspaceStore((s) => s.currentWorkspaceId)

  return useQuery({
    queryKey: peopleKey(wsId),
    queryFn: async (): Promise<PersonDTO[]> => {
      const members = await membershipsApi.list()
      return members
        .filter((m) => m.person_id)
        .map((m) => ({ id: m.person_id as string, name: m.name ?? '—' }))
    },
    enabled: Boolean(wsId),
  })
}

// A mutation de substituição invalida a lista de TAREFAS do robô — a tabela
// mostra os novos chips sem reload (§2.6/D9).
export function useReplaceAssignees(robotId: string) {
  const wsId = useWorkspaceStore((s) => s.currentWorkspaceId)
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: ({ taskId, personIds }: { taskId: string; personIds: string[] }) =>
      taskAssigneesApi.replace(taskId, personIds),
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: catalogKeys.robotTasks(wsId, robotId) })
    },
  })
}

// Estado do modal: quem está selecionado (partindo dos responsáveis atuais),
// o toggle, o cadastro-e-marca de pessoa nova, e o conjunto a enviar no PUT.
export function useAssigneeSelection(initialAssigneeIds: string[]) {
  const wsId = useWorkspaceStore((s) => s.currentWorkspaceId)
  const queryClient = useQueryClient()
  const [selected, setSelected] = useState<Set<string>>(() => new Set(initialAssigneeIds))

  const toggle = useCallback((id: string) => {
    setSelected((prev) => {
      const next = new Set(prev)
      if (next.has(id)) next.delete(id)
      else next.add(id)
      return next
    })
  }, [])

  // Cadastra a pessoa (uuid do cliente), semeia no cache de people para
  // sobreviver ao fechamento do modal, e já a marca como selecionada.
  const createAndSelect = useCallback(
    async (name: string): Promise<PersonDTO> => {
      const person = await peopleApi.create({ id: newId(), name: name.trim() })
      queryClient.setQueryData<PersonDTO[]>(peopleKey(wsId), (old) => {
        const list = old ?? []
        return list.some((p) => p.id === person.id) ? list : [...list, person]
      })
      setSelected((prev) => new Set(prev).add(person.id))
      return person
    },
    [wsId, queryClient],
  )

  return { selected, toggle, createAndSelect, personIds: () => [...selected] }
}
