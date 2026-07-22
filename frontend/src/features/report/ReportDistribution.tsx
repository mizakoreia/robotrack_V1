import type { CommissioningReportDTO } from './types'

// commissioning-report 4.2 (§3.8/§5.1, D-R10) — a distribuição de status. Os glifos
// `✓ ◐ ○ —` vêm do PAYLOAD (nunca digitados no JSX — repetir o caractere aqui seria
// o vetor pelo qual um emoji entra depois; §5.1). As 4 linhas vêm sempre, inclusive
// zeradas. Nada é somado no cliente (D-R1) — as contagens já vêm resolvidas.
export function ReportDistribution({ report }: { report: CommissioningReportDTO }) {
  return (
    <ul className="rpt-distribution flex flex-wrap gap-x-6 gap-y-1 text-sm">
      {report.status_distribution.map((row) => (
        <li key={row.status} className="flex items-center gap-2">
          <span aria-hidden="true" className="rpt-glyph w-4 text-center">
            {row.glyph}
          </span>
          <span className="text-text-muted">{row.label}</span>
          <span className="tabular font-semibold text-text-main">{row.count}</span>
        </li>
      ))}
    </ul>
  )
}
