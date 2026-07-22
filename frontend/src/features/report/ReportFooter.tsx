import type { CommissioningReportDTO } from './types'
import { reportDateTime } from './format'

// commissioning-report 7.1 (§3.8, D-R6) — o rodapé do documento: id CARIMBADO
// (byte a byte o dos metadados — o cliente não gera nem reformata id), data de
// geração e a nota de rastreabilidade, tudo do payload (D-R9). Vive no <tfoot>
// da tabela raiz (ReportDocument) para repetir em TODAS as páginas impressas
// reservando espaço (D-R3 — nunca position:fixed).
export function ReportFooter({ report }: { report: CommissioningReportDTO }) {
  const f = report.footer
  return (
    <div className="rpt-footer space-y-1 border-t pt-2 text-xs text-text-muted">
      <p className="flex flex-wrap gap-x-4">
        <span className="tabular font-medium">{f.document_id}</span>
        <span>
          {f.generated_at_label}{' '}
          <time dateTime={f.generated_at}>{reportDateTime(f.generated_at)}</time>
        </span>
      </p>
      <p>{f.traceability}</p>
    </div>
  )
}
