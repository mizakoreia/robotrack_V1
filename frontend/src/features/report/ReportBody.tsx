import type { CommissioningReportDTO, ReportRobotDTO, ReportTaskDTO, ReportAdvanceDTO } from './types'
import { reportDateTime } from './format'

// commissioning-report 5.4/7.4 (§3.8, D8/D11/D-R1/D-R4) — o corpo hierárquico:
// projeto → célula → robô, cada nível com barra de progresso PONDERADO rotulada
// (rótulo do payload, D-R9), o robô com sua Aplicação, e a tabela de tarefas com o
// histórico ABAIXO de cada tarefa. Tarefa SEM histórico não imprime bloco vazio
// (§3.8). Níveis vazios renderizam com barra 0% e sem estourar (§2.9/§1.4). Nada é
// recalculado (D-R1) — `%`, símbolos e transições vêm prontos do servidor.
//
// Quebra de página (D-R4): cada tarefa + TODO o seu histórico é um <tbody
// class="rpt-task"> indivisível (`break-inside: avoid`, report-print.css). Acima
// de HISTORY_PAGE_CHUNK entradas o bloco não caberia numa folha — degrada: o
// histórico é fatiado e cada fatia de continuação entra num <tbody> próprio,
// precedido da faixa `— histórico continua na próxima página —` (rótulo do
// servidor, D-R9), visível só na impressão.

// D-R4 — limiar de entradas acima do qual o bloco tarefa+histórico deixa de ser
// indivisível e passa a quebrar em fatias anunciadas.
export const HISTORY_PAGE_CHUNK = 18

type Labels = CommissioningReportDTO['labels']

function Bar({ value, label }: { value: number; label: string }) {
  return (
    <div className="rpt-bar flex items-center gap-2">
      <div className="rpt-bar-track h-1.5 w-40 overflow-hidden rounded-full bg-bg-sunken" role="progressbar" aria-valuenow={value} aria-valuemin={0} aria-valuemax={100}>
        <div className="rpt-bar-fill h-full bg-accent" style={{ width: `${value}%` }} />
      </div>
      <span className="label-sm tabular text-text-muted">
        {value}% <span className="text-text-muted/70">{label}</span>
      </span>
    </div>
  )
}

export function ReportBody({ report }: { report: CommissioningReportDTO }) {
  const L = report.labels
  return (
    <section className="rpt-body space-y-6">
      <h2 className="panel-header">{L.section_body}</h2>
      {report.tree.map((project) => (
        <div key={project.id} className="rpt-project space-y-3">
          <div className="rpt-level">
            <h3 className="font-semibold text-text-main">{project.name}</h3>
            <Bar value={project.weighted_progress} label={L.weighted_progress} />
          </div>
          {project.cells.length === 0 ? (
            <p className="pl-4 text-sm text-text-muted">—</p>
          ) : (
            project.cells.map((cell) => (
              <div key={cell.id} className="rpt-cell space-y-2 pl-4">
                <div className="rpt-level">
                  <h4 className="text-text-main">{cell.name}</h4>
                  <Bar value={cell.weighted_progress} label={L.weighted_progress} />
                </div>
                {cell.robots.length === 0 ? (
                  <p className="pl-4 text-sm text-text-muted">—</p>
                ) : (
                  cell.robots.map((robot) => <RobotBlock key={robot.id} robot={robot} labels={L} />)
                )}
              </div>
            ))
          )}
        </div>
      ))}
    </section>
  )
}

function RobotBlock({ robot, labels: L }: { robot: ReportRobotDTO; labels: Labels }) {
  return (
    <div className="rpt-robot space-y-2 pl-4">
      <div className="rpt-level flex flex-wrap items-center gap-3">
        <h5 className="font-medium text-text-main">{robot.name}</h5>
        {robot.application && <span className="label-sm text-text-muted">{robot.application}</span>}
        <Bar value={robot.weighted_progress} label={L.weighted_progress} />
      </div>
      <table className="rpt-tasks w-full border-collapse text-left text-sm">
        <thead>
          <tr className="label-sm text-text-muted">
            <th className="w-6 px-2 py-1">{L.col_symbol}</th>
            <th className="px-2 py-1">{L.col_description}</th>
            <th className="px-2 py-1">{L.col_status}</th>
            <th className="px-2 py-1">{L.col_percent}</th>
            <th className="px-2 py-1">{L.col_assignees}</th>
          </tr>
        </thead>
        {robot.tasks.map((task) => (
          <TaskRows key={task.id} task={task} labels={L} />
        ))}
      </table>
    </div>
  )
}

// Fatia o histórico em blocos de HISTORY_PAGE_CHUNK (sem reduce — regra ESLint da
// feature; fatiar não deriva número: os valores seguem os do servidor).
function chunkAdvances(advances: ReportAdvanceDTO[]): ReportAdvanceDTO[][] {
  const out: ReportAdvanceDTO[][] = []
  for (let i = 0; i < advances.length; i += HISTORY_PAGE_CHUNK) {
    out.push(advances.slice(i, i + HISTORY_PAGE_CHUNK))
  }
  return out
}

function TaskRows({ task, labels: L }: { task: ReportTaskDTO; labels: Labels }) {
  const chunks = chunkAdvances(task.advances)
  const long = task.advances.length > HISTORY_PAGE_CHUNK
  return (
    <>
      <tbody className={long ? 'rpt-task rpt-task--long' : 'rpt-task'}>
        <tr className="border-t align-top">
          <td className="rpt-glyph px-2 py-1 text-center" aria-hidden="true">{task.symbol}</td>
          <td className="px-2 py-1">{task.description}</td>
          <td className="px-2 py-1">{task.status}</td>
          <td className="tabular px-2 py-1">{task.percent}%</td>
          <td className="px-2 py-1">{task.assignees.length ? task.assignees.join(', ') : L.no_assignees}</td>
        </tr>
        {chunks.length > 0 && <HistoryRow advances={chunks[0]} labels={L} />}
      </tbody>
      {chunks.slice(1).map((slice, i) => (
        <tbody key={i} className="rpt-task-cont">
          <tr className="rpt-continuation">
            <td />
            <td colSpan={4} className="px-2 py-1 text-center text-xs text-text-muted">
              {L.history_continues}
            </td>
          </tr>
          <HistoryRow advances={slice} labels={L} />
        </tbody>
      ))}
    </>
  )
}

function HistoryRow({ advances, labels: L }: { advances: ReportAdvanceDTO[]; labels: Labels }) {
  return (
    <tr className="rpt-history">
      <td />
      <td colSpan={4} className="px-2 pb-2">
        <ul className="space-y-0.5 text-xs text-text-muted">
          {advances.map((a, i) => (
            <li key={i} className="flex flex-wrap gap-2">
              <time dateTime={a.recorded_at}>{reportDateTime(a.recorded_at)}</time>
              <span className="font-medium">{a.author ?? L.no_assignees}</span>
              <span className="tabular">{a.transition}</span>
              {a.comment && <span>— {a.comment}</span>}
            </li>
          ))}
        </ul>
      </td>
    </tr>
  )
}
