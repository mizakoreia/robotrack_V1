import { useMutation, useQueryClient } from '@tanstack/react-query'
import {
  taskAdvancesApi,
  type AdvanceConflict,
  type RecordAdvanceResult,
} from '../../lib/api/endpoints'
import { catalogKeys } from '../../lib/api/catalogKeys'
import { advanceKeys } from '../../lib/api/advanceKeys'
import { qk } from '../../lib/query/keys'
import { useWorkspaceStore } from '../../store/workspaceStore'

// progress-advances 5.4–5.5 (§2.4 item 4, D1/D8/D-409) — a mutation do registro
// de avanço e a leitura do conflito.
//
// O `uuid` é gerado FORA daqui (no componente, uma vez por rascunho): é a chave
// de idempotência (D1). Um duplo-clique manda o MESMO uuid e o backend responde
// 200 replay — a trilha ganha 1 entrada, não 2. Por isso a mutation não gera id.
//
// No sucesso, invalida DUAS chaves (5.4): as tarefas do robô (a tabela mostra o
// novo progresso) e a trilha da tarefa (o histórico ganha a entrada). Não há
// retry automático — mutations do React Query não retentam por padrão, e um 409
// jamais deve ser reenviado sozinho (D-409).

export interface RecordAdvanceVars {
  taskId: string
  id: string
  // XOR (§2.2): `toProgress` quando o gesto foi slider/±; `toStatus` quando foi o
  // StatusSelect (robot-task-table 2.1). Enviar status deixa a tabela-verdade com
  // o servidor — mandar `progress: 0` no lugar de `N/A` viraria `Pendente`.
  toProgress?: number
  toStatus?: string
  comment?: string
  recordedAt?: string
  lockVersion?: number
}

// Extrai o corpo do 409 do erro do axios; devolve null para qualquer outro erro.
export function readAdvanceConflict(error: unknown): AdvanceConflict | null {
  const resp = (error as { response?: { status?: number; data?: unknown } })?.response
  if (resp?.status !== 409) return null
  const data = resp.data as AdvanceConflict | undefined
  if (data?.error === 'conflito_de_versao') return data
  return null
}

export function useRecordAdvance(robotId: string) {
  const wsId = useWorkspaceStore((s) => s.currentWorkspaceId)
  const queryClient = useQueryClient()

  return useMutation<RecordAdvanceResult, unknown, RecordAdvanceVars>({
    // realtime-collaboration 6.2 — a `mutationKey` no ESCOPO do robô é o que o
    // gate usa para represar um evento de terceiro que chegue enquanto este POST
    // está em voo (intersecta `['ws',w,'robot',r]` e `…,'tasks']`), evitando o
    // flicker 60→40→60 na tabela.
    mutationKey: qk.robot(wsId ?? '_', robotId),
    mutationFn: (vars) =>
      taskAdvancesApi.create(vars.taskId, {
        id: vars.id,
        progress: vars.toProgress,
        status: vars.toStatus,
        comment: vars.comment,
        recorded_at: vars.recordedAt,
        lock_version: vars.lockVersion,
      }),
    onSuccess: (_result, vars) => {
      void queryClient.invalidateQueries({ queryKey: catalogKeys.robotTasks(wsId, robotId) })
      void queryClient.invalidateQueries({ queryKey: advanceKeys.trail(wsId, vars.taskId) })
      // robot-task-table 2.3 (D-RTT-10) — o avanço mexe nos agregados ponderados:
      // os anéis da hierarquia (prefixo `projects`) e o % do cabeçalho do robô
      // (`qk.robot` EXATO — o filho `…,'tasks'` já foi invalidado acima).
      void queryClient.invalidateQueries({ queryKey: qk.projects(wsId ?? '_') })
      void queryClient.invalidateQueries({ queryKey: qk.robot(wsId ?? '_', robotId), exact: true })
    },
  })
}
