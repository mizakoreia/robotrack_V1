import { useEffect, useState, Fragment } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { toast } from 'sonner'
import { Icon } from '@/components/icons/Icon'
import { Button } from '@/components/ui/Button'
import { Badge } from '@/components/ui/Badge'
import { BackLink } from '@/features/hierarchy/LevelChrome'
import { useRobotTasks, useRobotHeader, type TaskDTO } from '@/features/robot-tasks/useRobotTasks'
import { useRobotTaskFilter, applyFilter, type TaskFilter } from '@/features/robot-tasks/filterStore'
import { StatusCell } from '@/features/robot-tasks/StatusCell'
import { ResponsaveisCell } from '@/features/robot-tasks/ResponsaveisCell'
import { TrilhaCell } from '@/features/robot-tasks/TrilhaCell'
import { AcoesCell } from '@/features/robot-tasks/AcoesCell'
import { AddTaskModal } from '@/features/robot-tasks/AddTaskModal'
import { useSyncTemplates } from '@/features/robot-tasks/useTaskCrud'
import { AdvanceControls } from '@/features/advances/AdvanceControls'
import { useWorkspaceStore } from '@/store/workspaceStore'
import { robotTaskText } from '@/lib/i18n/robotTasks'
import { metricLabel } from '@/lib/i18n/progress'

// robot-task-table 1.4/1.5 (§3.5) — a casca da tela operacional do robô: cabeçalho,
// filtro segmentado (reset na navegação, D-RTT-1), tabela agrupada por categoria e os
// estados. Status e Progresso são interativos (G2, §2.2/§2.4): a célula de Status
// compõe o StatusSelect→modal; a de Progresso COMPÕE `<AdvanceControls>` de
// progress-advances (D-RTT-5 — `persisted` da query, `draft` local, ± do persistido).
// Responsáveis/Trilha/Ações continuam leitura até os grupos 3–4. A rota é montada
// com `key={robotId}` em App.tsx.
const FILTERS: { key: TaskFilter; label: string }[] = [
  { key: 'all', label: 'Todos' },
  { key: 'pending', label: 'Pendentes' },
  { key: 'done', label: 'Concluídos' },
]

export function RobotTaskTablePage() {
  const { id } = useParams<{ id: string }>()
  const robotId = id ?? null
  const navigate = useNavigate()
  const header = useRobotHeader(robotId)
  const { data: tasks, isLoading, isError, refetch } = useRobotTasks(robotId)
  const filter = useRobotTaskFilter((s) => s.filter)
  const setFilter = useRobotTaskFilter((s) => s.setFilter)
  const reset = useRobotTaskFilter((s) => s.reset)
  const role = useWorkspaceStore((s) => s.currentRoleLabel)
  const canEdit = role === 'owner' || role === 'edit'
  const [adding, setAdding] = useState(false)
  const sync = useSyncTemplates(robotId ?? '_')

  // D-RTT-1 — reset do filtro na navegação (o `key={robotId}` da rota cobre A→A).
  useEffect(() => reset(), [robotId, reset])

  // §2.6 — sincroniza as tarefas-base, informa a contagem e reseta o filtro para
  // "Todos" (as novas linhas aparecem mesmo se o filtro estava em "Concluídos").
  function runSync() {
    sync.mutate(undefined, {
      onSuccess: (res) => {
        setFilter('all')
        toast.success(res.addedCount > 0 ? robotTaskText.syncResult(res.addedCount) : robotTaskText.syncNone)
      },
    })
  }

  if (isLoading) return <TableSkeleton />
  if (isError || !tasks) return <TableError onRetry={() => void refetch()} />

  const visible = applyFilter(tasks, filter)
  const robotName = header.data?.name ?? 'Robô'

  return (
    <section aria-labelledby="robot-title" className="mx-auto max-w-6xl space-y-6">
      <BackLink label="Voltar à célula" onClick={() => navigate(header.data ? `/celula/${header.data.cell_id}` : '/')} />

      <header className="flex flex-wrap items-center justify-between gap-3">
        <div className="flex min-w-0 items-center gap-3">
          <h1 id="robot-title" className="title truncate">
            {robotName}
          </h1>
          {header.data && <Badge status="accent">{header.data.application}</Badge>}
        </div>
        {header.data && (
          <span
            className="label-md text-text-muted"
            aria-label={`${metricLabel('weighted')}: ${header.data.weighted_progress.value}%`}
          >
            <span className="title tabular text-text-main">{header.data.weighted_progress.value}%</span>{' '}
            {metricLabel('weighted')}
          </span>
        )}
      </header>

      {/* filtro + ações do cabeçalho. As ações (Adicionar/Sincronizar) só existem
          para owner/edit (4.4, D-RTT-9) — `view` não vê alvo desabilitado. */}
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div role="tablist" aria-label="Filtro de tarefas" className="surface-panel inline-flex gap-1 rounded-lg border p-1">
          {FILTERS.map((f) => (
            <button
              key={f.key}
              role="tab"
              aria-selected={filter === f.key}
              onClick={() => setFilter(f.key)}
              className={
                'label-md min-h-[2rem] rounded-md px-3 font-medium ' +
                (filter === f.key ? 'bg-accent/15 text-accent-ink' : 'text-text-muted hover:text-text-main')
              }
            >
              {f.label}
            </button>
          ))}
        </div>

        {canEdit && (
          <div className="flex flex-wrap items-center gap-2">
            <Button type="button" variant="outline" size="sm" onClick={runSync} disabled={sync.isPending}>
              <Icon name="list" size="sm" className="mr-1" />
              {sync.isPending ? robotTaskText.syncing : robotTaskText.syncTemplates}
            </Button>
            <Button type="button" size="sm" onClick={() => setAdding(true)}>
              <Icon name="plus" size="sm" className="mr-1" />
              {robotTaskText.addTask}
            </Button>
          </div>
        )}
      </div>

      {tasks.length === 0 ? (
        <TableEmpty robotName={robotName} />
      ) : (
        <TaskTable robotId={robotId ?? '_'} tasks={visible} canEdit={canEdit} />
      )}

      {canEdit && robotId && <AddTaskModal robotId={robotId} open={adding} onClose={() => setAdding(false)} />}
    </section>
  )
}

// A tabela agrupada por categoria (§3.5) — linha separadora na troca de categoria,
// preservando a ordem persistida das tarefas dentro do grupo.
function TaskTable({ robotId, tasks, canEdit }: { robotId: string; tasks: TaskDTO[]; canEdit: boolean }) {
  let lastCat: string | null = null
  // 4.4 (D-RTT-9) — a coluna Ações SAI do DOM para `view` (não é `disabled`); o
  // colSpan do separador acompanha (5 colunas sem Ações).
  const cols = canEdit ? 6 : 5
  return (
    <div className="surface-panel overflow-hidden rounded-lg border">
      <table className="w-full border-collapse text-left">
        <thead>
          <tr className="label-sm text-text-muted">
            <th className="px-4 py-2 font-medium">Tarefa</th>
            <th className="px-4 py-2 font-medium">Status</th>
            <th className="px-4 py-2 font-medium">Progresso</th>
            <th className="px-4 py-2 font-medium">Responsáveis</th>
            <th className="px-4 py-2 font-medium">Trilha</th>
            {canEdit && <th className="px-4 py-2 font-medium">Ações</th>}
          </tr>
        </thead>
        <tbody>
          {tasks.map((t) => {
            const newGroup = t.cat !== lastCat
            lastCat = t.cat
            return (
              <Fragment key={t.id}>
                {newGroup && (
                  <tr>
                    <td colSpan={cols} className="panel-header bg-accent/5 px-4 py-2 text-text-muted">
                      {t.cat}
                    </td>
                  </tr>
                )}
                <TaskRow robotId={robotId} task={t} canEdit={canEdit} />
              </Fragment>
            )
          })}
        </tbody>
      </table>
    </div>
  )
}

// Status e Progresso interativos (G2); Responsáveis e Trilha (G3); Ações (G4, só
// owner/edit). Os controles de mutação (StatusCell/AdvanceControls) já se auto-
// gateiam por papel; a coluna Ações é removida na TaskTable.
function TaskRow({ robotId, task, canEdit }: { robotId: string; task: TaskDTO; canEdit: boolean }) {
  return (
    <tr className="border-t align-top">
      <td className="px-4 py-3">{task.desc}</td>
      <td className="px-4 py-3 align-middle">
        <StatusCell robotId={robotId} task={task} />
      </td>
      <td className="px-4 py-3 align-middle">
        {/* leitura % + − slider + vivem no AdvanceControls (D-RTT-5) */}
        <AdvanceControls robotId={robotId} taskId={task.id} />
      </td>
      <td className="px-4 py-3">
        <ResponsaveisCell task={task} />
      </td>
      <td className="px-4 py-3">
        <TrilhaCell robotId={robotId} task={task} />
      </td>
      {canEdit && (
        <td className="px-4 py-3 align-middle">
          <AcoesCell robotId={robotId} task={task} />
        </td>
      )}
    </tr>
  )
}

function TableEmpty({ robotName }: { robotName: string }) {
  return (
    <div className="surface-panel flex flex-col items-center rounded-lg border p-10 text-center">
      <h2 className="panel-header mb-2">Nenhuma tarefa em {robotName}</h2>
      <p className="max-w-md text-text-muted">
        Adicione tarefas ou sincronize as tarefas-base para começar o comissionamento deste robô.
      </p>
    </div>
  )
}

function TableError({ onRetry }: { onRetry: () => void }) {
  return (
    <div className="surface-panel mx-auto mt-6 flex max-w-md flex-col items-center rounded-lg border p-10 text-center">
      <Icon name="alert" size="md" className="mb-2 text-danger-ink" />
      <p className="mb-4 text-text-muted">Não foi possível carregar as tarefas do robô.</p>
      <Button variant="outline" onClick={onRetry}>
        Tentar novamente
      </Button>
    </div>
  )
}

function TableSkeleton() {
  return (
    <section className="mx-auto max-w-6xl space-y-6" aria-busy="true" aria-label="Carregando">
      <div className="surface-panel h-8 w-48 animate-pulse rounded-lg border" />
      <div className="surface-panel h-64 animate-pulse rounded-lg border" />
    </section>
  )
}
