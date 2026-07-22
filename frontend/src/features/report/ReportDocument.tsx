import type { CommissioningReportDTO } from './types'
import { ReportHeader } from './ReportHeader'
import { ReportMetadata } from './ReportMetadata'
import { ReportDistribution } from './ReportDistribution'
import { ReportBody } from './ReportBody'
import { ReportConclusions } from './ReportConclusions'
import { ReportSignatures } from './ReportSignatures'
import { ReportFooter } from './ReportFooter'
import './report-print.css'

// commissioning-report 7.3 (D-R3) — a TABELA RAIZ de impressão. Cabeçalho corrido
// (título + id) no <thead> e rodapé no <tfoot>: o navegador os repete em TODAS as
// páginas impressas RESERVANDO espaço — `position: fixed` repetiria mas deixaria o
// corpo passar por baixo a partir da página 2. Na tela o corrido fica oculto
// (`.rpt-running`, só sob @media print); o rodapé aparece uma vez, no fim, como
// num documento normal.
export function ReportDocument({ report }: { report: CommissioningReportDTO }) {
  const L = report.labels
  return (
    <table className="rpt-doc w-full border-collapse">
      <thead className="rpt-running">
        <tr>
          <td className="pb-3">
            <div className="flex items-baseline justify-between border-b pb-1 text-xs text-text-muted">
              <span className="font-semibold tracking-wide">{report.header.title}</span>
              <span className="tabular">{report.document_id}</span>
            </div>
          </td>
        </tr>
      </thead>
      <tfoot>
        <tr>
          <td className="pt-4">
            <ReportFooter report={report} />
          </td>
        </tr>
      </tfoot>
      <tbody>
        <tr>
          <td>
            <div className="space-y-8">
              <ReportHeader report={report} />
              <ReportMetadata report={report} />
              <section className="rpt-distribution-section space-y-2">
                <h2 className="panel-header">{L.section_distribution}</h2>
                <ReportDistribution report={report} />
              </section>
              <ReportBody report={report} />
              <ReportConclusions report={report} />
              <ReportSignatures report={report} />
            </div>
          </td>
        </tr>
      </tbody>
    </table>
  )
}
