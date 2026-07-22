import type { CommissioningReportDTO } from './types'
import { reportDateTime } from './format'

// commissioning-report 3.2/8.2 (§3.8, D-R6/D-R9) — o bloco de metadados: escopo,
// id do documento, data/hora de emissão, quem gerou, e a estrutura. Tudo já
// resolvido no payload — INCLUSIVE os rótulos (`labels.meta_*`, D-R9; o sweep de
// literais reprova pt-BR fixo aqui). O id NÃO é reformatado (D-R6) e a estrutura é
// uma string pronta. O componente só formata a DATA de exibição de `issued_at`.
export function ReportMetadata({ report }: { report: CommissioningReportDTO }) {
  const m = report.metadata
  const L = report.labels
  const rows: [string, string | null][] = [
    [L.meta_scope, m.scope_label],
    [L.meta_document_id, m.document_id],
    [L.meta_issued_at, reportDateTime(m.issued_at)],
    [L.meta_generated_by, m.generated_by],
    [L.meta_structure, m.structure],
  ]
  return (
    <dl className="rpt-meta grid grid-cols-[auto_1fr] gap-x-4 gap-y-1 text-sm">
      {rows.map(([label, value]) => (
        <div key={label} className="contents">
          <dt className="text-text-muted">{label}</dt>
          <dd className="tabular text-text-main">{value ?? '—'}</dd>
        </div>
      ))}
    </dl>
  )
}
