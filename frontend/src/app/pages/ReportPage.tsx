import { useEffect, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { Button } from '@/components/ui/Button'
import { useReport } from '../../features/report/useReport'
import { ReportDocument } from '../../features/report/ReportDocument'
import { hierarchyApi } from '../../lib/api/endpoints'
import { qk } from '../../lib/query/keys'
import { useWorkspaceStore } from '../../store/workspaceStore'
import { reportText as T } from '../../lib/i18n/report'

// commissioning-report 8.3 (§4.3) — a tela do Protocolo: seletor de escopo
// (workspace inteiro | um projeto), o documento congelado (ReportDocument) e os
// TRÊS estados fora do feliz — carregando, erro acionável e offline explícito.
// O documento NUNCA aparece pela metade: ou o payload inteiro chegou, ou a tela
// mostra estado. O chrome da tela (seletor/botões) não sai no papel
// (`rpt-no-print`, report-print.css).
export function ReportPage() {
  const [scope, setScope] = useState<string>('all') // 'all' | projectId
  const projectId = scope === 'all' ? undefined : scope
  const { data: report, isLoading, isError, error, refetch } = useReport(projectId ? 'project' : 'all', projectId)
  const online = useOnline()

  const wsId = useWorkspaceStore((s) => s.currentWorkspaceId)
  const { data: projects } = useQuery({
    queryKey: qk.projects(wsId ?? '_'),
    queryFn: () => hierarchyApi.listProjects(),
    enabled: Boolean(wsId),
  })

  return (
    <section aria-labelledby="report-title" className="mx-auto max-w-4xl space-y-6">
      <div className="rpt-no-print flex flex-wrap items-center justify-between gap-3">
        <h1 id="report-title" className="title">
          {T.title}
        </h1>
        <div className="flex items-center gap-3">
          <label className="label-sm flex items-center gap-2 text-text-muted">
            {T.scopeLabel}
            <select
              className="input h-9 rounded-md border bg-bg-main px-2 text-sm text-text-main"
              value={scope}
              onChange={(e) => setScope(e.target.value)}
            >
              <option value="all">{T.scopeAll}</option>
              {(projects ?? []).map((p) => (
                <option key={p.id} value={p.id}>
                  {p.name}
                </option>
              ))}
            </select>
          </label>
          {report && (
            <Button type="button" onClick={() => window.print()}>
              {T.print}
            </Button>
          )}
        </div>
      </div>

      {report ? (
        <ReportDocument report={report} />
      ) : !online ? (
        // §4.3 — sem conexão a query fica PAUSADA (networkMode online): informar
        // explicitamente, nunca girar um loading eterno nem montar doc parcial.
        <ErrorState offline onRetry={() => void refetch()} />
      ) : isLoading ? (
        <p role="status" className="text-text-muted">
          {T.loading}
        </p>
      ) : isError ? (
        <ErrorState offline={isNetworkError(error)} onRetry={() => void refetch()} />
      ) : null}
    </section>
  )
}

// §4.3 — a falha de REDE do axios (sem resposta do servidor) também é "offline",
// distinta do erro de servidor (500 etc.).
function isNetworkError(error: unknown): boolean {
  const e = error as { response?: unknown; code?: string }
  return !e?.response && e?.code === 'ERR_NETWORK'
}

function useOnline(): boolean {
  const [online, setOnline] = useState(() => typeof navigator === 'undefined' || navigator.onLine)
  useEffect(() => {
    const on = () => setOnline(true)
    const off = () => setOnline(false)
    window.addEventListener('online', on)
    window.addEventListener('offline', off)
    return () => {
      window.removeEventListener('online', on)
      window.removeEventListener('offline', off)
    }
  }, [])
  return online
}

function ErrorState({ offline, onRetry }: { offline: boolean; onRetry: () => void }) {
  return (
    <div role="alert" className="surface-panel space-y-3 rounded-lg border p-6">
      <p className="font-medium text-text-main">{offline ? T.offlineTitle : T.errorTitle}</p>
      <p className="text-sm text-text-muted">{offline ? T.offlineBody : T.errorBody}</p>
      <Button type="button" variant="secondary" onClick={onRetry}>
        {T.retry}
      </Button>
    </div>
  )
}
