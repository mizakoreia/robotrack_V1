import { useReport } from '../../features/report/useReport'
import { ReportDocument } from '../../features/report/ReportDocument'

// commissioning-report — a página do Protocolo. No G6 ela monta o DOCUMENTO
// (necessário ao teste de impressão A4, 7.5): payload congelado do servidor →
// ReportDocument (tabela raiz de impressão, D-R3). O seletor de escopo e os
// estados de carregamento/erro/offline entram no G7 (8.3).
export function ReportPage() {
  const { data: report } = useReport('all')
  return (
    <section aria-labelledby="report-title" className="mx-auto max-w-4xl">
      <h1 id="report-title" className="sr-only">
        Relatório
      </h1>
      {report && <ReportDocument report={report} />}
    </section>
  )
}
