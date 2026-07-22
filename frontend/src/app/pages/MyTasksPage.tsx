import { useNavigate } from 'react-router-dom'
import { Badge, type BadgeStatus } from '@/components/ui/Badge'
import { Button } from '@/components/ui/Button'
import { Icon } from '@/components/icons/Icon'
import { useMyTasks, useMyTasksLive, isPersonMissing, type MyTaskRowDTO } from '@/features/my-tasks/useMyTasks'
import { myTasksText } from '@/lib/i18n/myTasks'
import { useMediaQuery } from '@/lib/useMediaQuery'

// my-tasks-view 6.x (§3.6, D-MTV-8/9) — a lista pessoal do viewer. LEITURA PURA:
// nenhum controle de mutação (o status é Badge estático, não seletor — mudar
// status é na tela do robô). Três estados DISTINTOS (D-MTV-8): vazio legítimo,
// identidade ausente (409) e erro de rede — o 409 NUNCA se parece com o vazio. A
// linha é um `<a>` deep-link para a tarefa no robô (D-MTV-9), navegável por teclado.

const STATUS_COLOR: Record<MyTaskRowDTO['status'], BadgeStatus> = {
  Pendente: 'warning',
  'Em Andamento': 'accent',
}

// D-MTV-9 — a rota REAL do robô é `/robo/:id`; a tarefa vai como query string
// (sobrevive ao roteador e ao service worker). Realçar/rolar até ela ao chegar é
// de robot-task-table.
function taskHref(row: MyTaskRowDTO): string {
  return `/robo/${encodeURIComponent(row.robot_id)}?task=${encodeURIComponent(row.id)}`
}

export function MyTasksPage() {
  const { data, isLoading, isError, error, refetch } = useMyTasks()
  useMyTasksLive() // 6.6 — invalida ao vivo em eventos de tarefa/atribuição

  return (
    <section aria-labelledby="my-tasks-title" className="mx-auto max-w-5xl space-y-6">
      <h1 id="my-tasks-title" className="title">
        {myTasksText.title}
      </h1>

      {isLoading ? (
        <Skeleton />
      ) : isError ? (
        isPersonMissing(error) ? (
          <IdentityMissing onRetry={() => void refetch()} />
        ) : (
          <LoadError onRetry={() => void refetch()} />
        )
      ) : !data || data.length === 0 ? (
        <EmptyState />
      ) : (
        <TaskList rows={data} />
      )}
    </section>
  )
}

function TaskList({ rows }: { rows: MyTaskRowDTO[] }) {
  // §6.5 (mesma técnica da tela do robô) — um layout por vez: tabela em md+,
  // cartões abaixo (caminho projeto/célula/robô como linha secundária), sem
  // rolagem horizontal em 375px.
  const isDesktop = useMediaQuery('(min-width: 768px)')

  if (!isDesktop) {
    return (
      <ul className="space-y-3">
        {rows.map((r) => (
          <li key={r.id}>
            <MobileCard row={r} />
          </li>
        ))}
      </ul>
    )
  }

  return (
    <div className="surface-panel overflow-hidden rounded-lg border">
      <table className="w-full border-collapse text-left">
        <thead>
          <tr className="label-sm text-text-muted">
            <th className="px-4 py-2 font-medium">{myTasksText.colTask}</th>
            <th className="px-4 py-2 font-medium">{myTasksText.colStatus}</th>
            <th className="px-4 py-2 font-medium">{myTasksText.colProgress}</th>
            <th className="px-4 py-2 font-medium">{myTasksText.colRobot}</th>
            <th className="px-4 py-2 font-medium">{myTasksText.colCell}</th>
            <th className="px-4 py-2 font-medium">{myTasksText.colProject}</th>
          </tr>
        </thead>
        <tbody>
          {rows.map((r) => (
            <TaskRow key={r.id} row={r} />
          ))}
        </tbody>
      </table>
    </div>
  )
}

// A linha inteira é clicável: o `<a>` cobre a primeira célula (preserva teclado,
// foco e "abrir em nova aba") — nunca um `onClick` numa `div` (D-MTV-9, a11y).
function TaskRow({ row }: { row: MyTaskRowDTO }) {
  return (
    <tr className="border-t align-middle hover:bg-accent/5">
      <td className="px-4 py-3">
        <a
          href={taskHref(row)}
          aria-label={myTasksText.openTaskAria(row.description, row.robot_name)}
          className="flex min-h-[40px] items-center font-medium text-text-main hover:underline"
        >
          {row.description}
        </a>
      </td>
      <td className="px-4 py-3">
        <Badge status={STATUS_COLOR[row.status]}>{row.status}</Badge>
      </td>
      <td className="px-4 py-3 tabular-nums">{row.progress}%</td>
      <td className="px-4 py-3 text-text-muted">{row.robot_name}</td>
      <td className="px-4 py-3 text-text-muted">{row.cell_name}</td>
      <td className="px-4 py-3 text-text-muted">{row.project_name}</td>
    </tr>
  )
}

function MobileCard({ row }: { row: MyTaskRowDTO }) {
  return (
    <a
      href={taskHref(row)}
      aria-label={myTasksText.openTaskAria(row.description, row.robot_name)}
      className="surface-panel block rounded-lg border p-4 hover:bg-accent/5"
    >
      <div className="flex items-start justify-between gap-2">
        <span className="font-medium text-text-main">{row.description}</span>
        <Badge status={STATUS_COLOR[row.status]}>{row.status}</Badge>
      </div>
      <div className="mt-1 tabular-nums text-text-muted">{row.progress}%</div>
      {/* caminho projeto/célula/robô como linha secundária (§6.5) */}
      <div className="label-sm mt-2 text-text-muted">
        {row.project_name} · {row.cell_name} · {row.robot_name}
      </div>
    </a>
  )
}

function EmptyState() {
  const navigate = useNavigate()
  return (
    <div className="surface-panel flex flex-col items-center rounded-lg border p-10 text-center">
      <h2 className="panel-header mb-2">{myTasksText.emptyTitle}</h2>
      <p className="mb-4 max-w-md text-text-muted">{myTasksText.emptyBody}</p>
      <Button variant="outline" onClick={() => navigate('/')}>
        {myTasksText.emptyAction}
      </Button>
    </div>
  )
}

function IdentityMissing({ onRetry }: { onRetry: () => void }) {
  return (
    <div role="alert" className="surface-panel flex flex-col items-center rounded-lg border p-10 text-center">
      <Icon name="alert" size="md" className="mb-2 text-warning-ink" />
      <h2 className="panel-header mb-2">{myTasksText.identityTitle}</h2>
      <p className="mb-4 max-w-md text-text-muted">{myTasksText.identityBody}</p>
      <Button variant="outline" onClick={onRetry}>
        {myTasksText.retry}
      </Button>
    </div>
  )
}

function LoadError({ onRetry }: { onRetry: () => void }) {
  return (
    <div className="surface-panel flex flex-col items-center rounded-lg border p-10 text-center">
      <Icon name="alert" size="md" className="mb-2 text-danger-ink" />
      <h2 className="panel-header mb-2">{myTasksText.errorTitle}</h2>
      <p className="mb-4 max-w-md text-text-muted">{myTasksText.errorBody}</p>
      <Button variant="outline" onClick={onRetry}>
        {myTasksText.retry}
      </Button>
    </div>
  )
}

function Skeleton() {
  return (
    <div
      className="surface-panel h-64 animate-pulse rounded-lg border"
      aria-busy="true"
      aria-label={myTasksText.loading}
    />
  )
}
