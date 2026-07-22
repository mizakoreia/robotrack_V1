import type { CommissioningReportDTO } from './types'

// commissioning-report 7.1 (§3.8) — os DOIS blocos de assinatura (Comissionador e
// Cliente / Aceite), cada um com linha para nome, assinatura e data — SEMPRE em
// branco: nada é pré-preenchido com o usuário logado (a assinatura é manuscrita,
// no papel). Rótulos vêm do payload (D-R9). O bloco é indivisível na quebra de
// página (`.rpt-signatures`, report-print.css).
export function ReportSignatures({ report }: { report: CommissioningReportDTO }) {
  const L = report.labels
  const lines = [L.signature_name, L.signature_field, L.signature_date]
  return (
    <section className="rpt-signatures grid grid-cols-2 gap-10 pt-8">
      {report.signatures.map((block) => (
        <div key={block.key} className="space-y-6">
          <h2 className="panel-header">{block.label}</h2>
          {lines.map((label) => (
            <div key={label} className="flex items-end gap-3">
              <span className="label-sm w-20 shrink-0 text-text-muted">{label}</span>
              <span className="rpt-sign-line block h-6 flex-1 border-b border-text-muted/50" />
            </div>
          ))}
        </div>
      ))}
    </section>
  )
}
