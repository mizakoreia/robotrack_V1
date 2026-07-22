import type { CommissioningReportDTO } from './types'

// commissioning-report 2.3 (§3.8, D-R1/D-R9) — o cabeçalho do documento: título,
// nome do workspace e o carimbo. TODOS os textos vêm resolvidos do payload (o
// título é `report.v1.title` no servidor; o front não tem cópia — D-R9). O carimbo
// é `percent · label` já derivado — o componente NÃO recalcula (a regra ESLint de
// `features/report/` proíbe `reduce`/`Math.round` justamente para impedir isso).

export function ReportHeader({ report }: { report: CommissioningReportDTO }) {
  const { header, stamp } = report
  return (
    <header className="rpt-header flex items-start justify-between gap-6 border-b pb-4">
      <div className="min-w-0">
        <h1 className="title tracking-wide">{header.title}</h1>
        {header.workspace_name && <p className="mt-1 text-text-muted">{header.workspace_name}</p>}
      </div>
      <div className="rpt-stamp shrink-0 rounded-lg border px-4 py-2 text-right">
        <div className="title tabular text-text-main">{stamp.percent}%</div>
        <div className="label-sm font-semibold tracking-wide text-text-muted">{stamp.label}</div>
      </div>
    </header>
  )
}
