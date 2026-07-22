import { useQuery } from '@tanstack/react-query'
import { reportApi } from '../../lib/api/endpoints'
import { qk } from '../../lib/query/keys'
import { useWorkspaceStore } from '../../store/workspaceStore'

// commissioning-report — a leitura do documento. Chave `qk.report` (D9,
// `['ws', wsId, 'report', scope]`); `networkMode: 'online'` + sem cache reidratado
// parcial: o documento é emitido INTEIRO do servidor ou não é emitido (§4.3 — a
// tela de estados/seletor entra no G7/8.3).
export function useReport(scope: 'all' | 'project', projectId?: string) {
  const wsId = useWorkspaceStore((s) => s.currentWorkspaceId)
  const scopeKey = scope === 'project' && projectId ? projectId : 'all'
  return useQuery({
    queryKey: qk.report(wsId ?? '_', scopeKey),
    queryFn: () => reportApi.get(scope, projectId),
    enabled: Boolean(wsId),
    networkMode: 'online',
    staleTime: 0,
  })
}
