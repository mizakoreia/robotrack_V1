import { Modal } from '@/components/ui/Modal'
import { useAuditLogs, type AuditLogDTO } from './useAuditLogs'
import { auditText } from '@/lib/i18n/audit'

// audit-log 6.2 (§2.8, Decisão 4) — o modal de auditoria. Consome `msg` e
// `ts_local` VERBATIM (o servidor renderizou e congelou; reformatar a data no
// cliente faria o mesmo registro mudar de texto conforme o fuso do navegador de
// quem lê — Decisão 4). A ordem já vem `ts DESC` do servidor; o cliente NÃO
// reordena. Sem controle de escrita/edição/exclusão em lugar nenhum (§4.1 inv. 3 +
// o REVOKE do banco fariam a chamada explodir). Estados vazio e de erro distintos.
//
// A montagem na tela de Configurações (Utilitários) é de `workspace-settings`; aqui
// o componente + o gatilho `open/onClose`, testável isolado.

// §2.8 — teto de EXIBIÇÃO de 200 (o servidor já clampa; isto é a rede do cliente
// se algum dia a fonte mudar). Sem reordenar: fatiar os 200 primeiros de uma lista
// `ts DESC` mantém os 200 MAIS RECENTES.
export const AUDIT_DISPLAY_LIMIT = 200

export function AuditLogModal({ open, onClose }: { open: boolean; onClose: () => void }) {
  const { data, isLoading, isError } = useAuditLogs(open)
  const rows = (data ?? []).slice(0, AUDIT_DISPLAY_LIMIT)

  return (
    <Modal open={open} onClose={onClose} title={auditText.title}>
      <p className="label-sm mb-3 text-text-muted">{auditText.subtitle}</p>
      {isLoading ? (
        <p className="text-text-muted">{auditText.loading}</p>
      ) : isError ? (
        <p className="text-danger-ink" role="alert">
          {auditText.loadError}
        </p>
      ) : rows.length === 0 ? (
        <p className="text-text-muted">{auditText.empty}</p>
      ) : (
        <ol className="rpt-audit-list space-y-2">
          {rows.map((log) => (
            <AuditRow key={log.id} log={log} />
          ))}
        </ol>
      )}
    </Modal>
  )
}

function AuditRow({ log }: { log: AuditLogDTO }) {
  return (
    <li className="border-l-2 border-accent/40 pl-3 text-sm">
      <p className="text-text-main">{log.msg}</p>
      {/* ts_local verbatim do servidor; `ts` (ISO) só na semântica do <time> */}
      <time dateTime={log.ts} className="label-sm tabular text-text-muted">
        {log.ts_local}
      </time>
    </li>
  )
}
