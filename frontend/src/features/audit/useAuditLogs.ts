import { useQuery } from '@tanstack/react-query'
import { auditLogsApi } from '../../lib/api/endpoints'
import { qk } from '../../lib/query/keys'
import { useWorkspaceStore } from '../../store/workspaceStore'

export type { AuditLogDTO } from '../../lib/api/endpoints'

// audit-log 6.1 (§2.8, D9) — a leitura do log. Chave `qk.auditLogs` (= `['ws',
// wsId, 'auditLogs']`), partindo por workspace: a troca de workspace descarta o
// cache (clear() no shell), e `realtime-collaboration` invalida exatamente esta
// chave depois. O teto de 200 é do servidor; o cliente não pagina. `enabled` só
// quando o modal abre (não busca o log em toda tela).
export function useAuditLogs(enabled: boolean) {
  const wsId = useWorkspaceStore((s) => s.currentWorkspaceId)
  return useQuery({
    queryKey: qk.auditLogs(wsId ?? '_'),
    queryFn: () => auditLogsApi.list(),
    enabled: enabled && Boolean(wsId),
  })
}
