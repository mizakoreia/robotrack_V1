import type { CommissioningReportDTO } from './types'
import { reportDateTime } from './format'

// commissioning-report 6.3 (§3.8, D-R7) — a seção Conclusões: as tarefas a 100% do
// escopo, com quem concluiu e quando (já resolvidos no servidor — autor da entrada
// que chegou a 100, com fallbacks; D-R7). O cliente não escolhe autoria (D-R1). Se
// não há conclusões, a seção não aparece.
export function ReportConclusions({ report }: { report: CommissioningReportDTO }) {
  const { conclusions, labels: L } = report
  if (conclusions.length === 0) return null
  return (
    <section className="rpt-conclusions space-y-2">
      <h2 className="panel-header">{L.section_conclusions}</h2>
      <ul className="space-y-1 text-sm">
        {conclusions.map((c) => (
          <li key={c.task_id} className="flex flex-wrap items-baseline gap-x-3">
            <span className="font-medium text-text-main">{c.description}</span>
            <span className="text-text-muted">
              {L.concluded_by}: {c.concluded_by}
            </span>
            {c.concluded_at && (
              <span className="text-text-muted">
                {L.concluded_at} <time dateTime={c.concluded_at}>{reportDateTime(c.concluded_at)}</time>
              </span>
            )}
          </li>
        ))}
      </ul>
    </section>
  )
}
