import { useQuery, useQueryClient } from '@tanstack/react-query'
import { myTasksApi } from '../../lib/api/endpoints'
import { qk } from '../../lib/query/keys'
import { useWorkspaceStore } from '../../store/workspaceStore'
import { useChannel } from '../../hooks/useCable'

export type { MyTaskRowDTO } from '../../lib/api/endpoints'

// my-tasks-view 6.1 (§3.6, D9) — a leitura da lista pessoal. UMA query na chave
// `qk.myTasks` (= `['ws', wsId, 'my-tasks']`), partindo por workspace: a troca de
// workspace no shell descarta o cache anterior (switchWorkspace faz `clear()`), e
// `realtime-collaboration` invalida exatamente esta chave. Nenhuma célula importa
// `apiClient` (a tela consome só este hook).
export function useMyTasks() {
  const wsId = useWorkspaceStore((s) => s.currentWorkspaceId)
  return useQuery({
    queryKey: qk.myTasks(wsId ?? '_'),
    queryFn: () => myTasksApi.list(),
    enabled: Boolean(wsId),
    // 409 (identidade ausente) e 5xx NÃO são retentados como rede: o 409 é um
    // estado do produto (mostra a tela de identidade), não uma falha transitória.
    retry: (count, error) => !isPersonMissing(error) && count < 1,
  })
}

// D-MTV-2/D-MTV-8 — distingue o 409 `person_missing` de qualquer outro erro. É o
// que impede o cliente de colapsar "sem cadastro" em "lista vazia".
export function isPersonMissing(error: unknown): boolean {
  const resp = (error as { response?: { status?: number; data?: { error?: string } } })?.response
  return resp?.status === 409 && resp?.data?.error === 'person_missing'
}

// my-tasks-view 6.6 (D6) — assina os eventos de tarefa/atribuição do
// `WorkspaceChannel` e invalida `qk.myTasks` (o usuário conclui a tarefa no robô,
// volta, e ela já saiu da lista). Degrada em silêncio se o canal ainda não existir
// (realtime-collaboration) — a tela funciona com o refetch normal. O descarte na
// TROCA de workspace é do shell (clear()); aqui é só a atualização ao vivo.
const LIVE_EVENTS = new Set(['task.advanced', 'task.assigned', 'task.updated'])

export function useMyTasksLive() {
  const wsId = useWorkspaceStore((s) => s.currentWorkspaceId)
  const queryClient = useQueryClient()

  // `useChannel` re-subscreve quando `workspace_id` muda, então o handler carrega
  // sempre o `wsId` corrente na closure — sem ref manual.
  useChannel(
    'WorkspaceChannel',
    { workspace_id: wsId ?? '' },
    {
      received: (data: { type?: string }) => {
        if (wsId && data?.type && LIVE_EVENTS.has(data.type)) {
          void queryClient.invalidateQueries({ queryKey: qk.myTasks(wsId) })
        }
      },
    },
  )
}
