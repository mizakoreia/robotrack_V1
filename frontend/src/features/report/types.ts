// commissioning-report — a feature reexporta os tipos do payload para que os
// componentes do documento (em app/ e features/report/) não importem `lib/api`
// direto (convenção D9/D-RTT-10). O documento é CONGELADO: os componentes só
// renderizam campos já derivados pelo servidor (D-R1) — nada de reduce/Math.round
// aqui (a regra ESLint de features/report/ reprova).
export type {
  CommissioningReportDTO,
  ReportProjectDTO,
  ReportCellDTO,
  ReportRobotDTO,
  ReportTaskDTO,
  ReportAdvanceDTO,
} from '../../lib/api/endpoints'
