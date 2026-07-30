import { useCallback, useEffect, useState, memo } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { toast } from 'sonner'
import { Icon } from '@/components/icons/Icon'
import { Button } from '@/components/ui/Button'
import { Modal } from '@/components/ui/Modal'
import { Badge } from '@/components/ui/Badge'
import { BackLink } from '@/features/hierarchy/LevelChrome'
import { useRobotTasks, useRobotHeader, type TaskDTO } from '@/features/robot-tasks/useRobotTasks'
import { useRobotTaskFilter, applyFilter, type TaskFilter } from '@/features/robot-tasks/filterStore'
import { StatusCell } from '@/features/robot-tasks/StatusCell'
import { ResponsaveisCell } from '@/features/robot-tasks/ResponsaveisCell'
import { TrilhaCell } from '@/features/robot-tasks/TrilhaCell'
import { AcoesCell } from '@/features/robot-tasks/AcoesCell'
import { AddTaskModal } from '@/features/robot-tasks/AddTaskModal'
import { useSyncTemplates, useBulkDeleteTasks } from '@/features/robot-tasks/useTaskCrud'
import { groupByCategory, groupLetter, useCategoryCollapse } from '@/features/robot-tasks/taskGroups'
import { useSuccessPulse } from '@/features/robot-tasks/useSuccessPulse'
import { useMediaQuery } from '@/lib/useMediaQuery'
import { AdvanceControls } from '@/features/advances/AdvanceControls'
import { useWorkspaceStore } from '@/store/workspaceStore'
import { robotTaskText } from '@/lib/i18n/robotTasks'
import { pagesText } from '@/lib/i18n/pages'
import { metricLabel } from '@/lib/i18n/progress'
import { applicationLabel, categoryLabel, baseTaskLabel } from '@/lib/i18n/dataLabels'
import { NotificationPreferenceControl } from '@/features/notifications/NotificationPreferenceControl'

// robot-task-table 1.4/1.5 (§3.5) — a casca da tela operacional do robô: cabeçalho,
// filtro segmentado (reset na navegação, D-RTT-1), tabela agrupada por categoria e os
// estados. Status e Progresso são interativos (G2, §2.2/§2.4): a célula de Status
// compõe o StatusSelect→modal; a de Progresso COMPÕE `<AdvanceControls>` de
// progress-advances (D-RTT-5 — `persisted` da query, `draft` local, ± do persistido).
// Responsáveis/Trilha/Ações continuam leitura até os grupos 3–4. A rota é montada
// com `key={robotId}` em App.tsx. Os rótulos das abas são CHROME (não os valores de
// status do banco) — resolvidos por `pagesText` no render (o remount por idioma relê).
function filterOptions(): { key: TaskFilter; label: string }[] {
  return [
    { key: 'all', label: pagesText.robotTask.filterAll },
    { key: 'pending', label: pagesText.robotTask.filterPending },
    { key: 'done', label: pagesText.robotTask.filterDone },
  ]
}

// robot-task-grouping G3 — a seleção múltipla existe só para o dono (`null` para os
// demais → sem checkboxes nem barra de ação). O servidor é a garantia (403).
type Selection = { selected: Set<string>; toggle: (id: string) => void } | null

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
  // owner-only-card-delete: excluir tarefa é só do dono; editar segue owner+edit.
  const isOwner = role === 'owner'
  const [adding, setAdding] = useState(false)
  const sync = useSyncTemplates(robotId ?? '_')

  // Seleção múltipla (owner). `toggle` é estável; o `key={robotId}` da rota já zera
  // o estado ao trocar de robô.
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set())
  const [confirmingBulk, setConfirmingBulk] = useState(false)
  const bulkDelete = useBulkDeleteTasks(robotId ?? '_')
  const toggleSelect = useCallback((tid: string) => {
    setSelectedIds((prev) => {
      const next = new Set(prev)
      if (next.has(tid)) next.delete(tid)
      else next.add(tid)
      return next
    })
  }, [])
  const sel: Selection = isOwner ? { selected: selectedIds, toggle: toggleSelect } : null

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
  const robotName = header.data?.name ?? pagesText.robotTask.robotFallback

  return (
    <section aria-labelledby="robot-title" className="mx-auto max-w-6xl space-y-6">
      <BackLink label={pagesText.robotTask.backToCell} onClick={() => navigate(header.data ? `/celula/${header.data.cell_id}` : '/')} />

      <header className="flex flex-wrap items-center justify-between gap-3">
        <div className="flex min-w-0 items-center gap-3">
          <h1 id="robot-title" className="title truncate">
            {robotName}
          </h1>
          {header.data && <Badge status="accent">{applicationLabel(header.data.application)}</Badge>}
        </div>
        {header.data && (
          <div className="flex items-center gap-2">
            <span
              className="label-md text-text-muted"
              aria-label={`${metricLabel('weighted')}: ${header.data.weighted_progress.value}%`}
            >
              <span className="title tabular text-text-main">{header.data.weighted_progress.value}%</span>{' '}
              {metricLabel('weighted')}
            </span>
            <NotificationPreferenceControl
              scope="robot"
              ancestry={[
                { type: 'robot', id: header.data.id },
                { type: 'cell', id: header.data.cell_id },
              ]}
            />
          </div>
        )}
      </header>

      {/* filtro + ações do cabeçalho. As ações (Adicionar/Sincronizar) só existem
          para owner/edit (4.4, D-RTT-9) — `view` não vê alvo desabilitado. */}
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div role="tablist" aria-label={pagesText.robotTask.filterLabel} className="surface-panel inline-flex gap-1 rounded-lg border p-1">
          {filterOptions().map((f) => (
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

      {/* robot-task-grouping G3 — barra de ação da seleção (owner). Aparece só com
          ≥1 marcada; excluir abre a confirmação; limpar zera a seleção. */}
      {sel && selectedIds.size > 0 && (
        <div className="surface-panel flex flex-wrap items-center justify-between gap-3 rounded-lg border px-4 py-2">
          <span className="label-md text-text-main">{robotTaskText.selectedCount(selectedIds.size)}</span>
          <div className="flex items-center gap-2">
            <Button type="button" variant="outline" size="sm" onClick={() => setSelectedIds(new Set())}>
              {robotTaskText.clearSelection}
            </Button>
            <Button type="button" variant="destructive" size="sm" onClick={() => setConfirmingBulk(true)}>
              <Icon name="trash" size="sm" className="mr-1" />
              {robotTaskText.bulkDelete}
            </Button>
          </div>
        </div>
      )}

      {tasks.length === 0 ? (
        <TableEmpty robotName={robotName} />
      ) : (
        <TaskTable robotId={robotId ?? '_'} tasks={visible} canEdit={canEdit} isOwner={isOwner} sel={sel} />
      )}

      {canEdit && robotId && <AddTaskModal robotId={robotId} open={adding} onClose={() => setAdding(false)} />}

      {sel && (
        <Modal
          open={confirmingBulk}
          onClose={() => setConfirmingBulk(false)}
          title={robotTaskText.bulkDeleteTitle}
          footer={
            <>
              <Button type="button" variant="outline" onClick={() => setConfirmingBulk(false)}>
                {robotTaskText.cancel}
              </Button>
              <Button
                type="button"
                variant="destructive"
                disabled={bulkDelete.isPending}
                onClick={() =>
                  bulkDelete.mutate([...selectedIds], {
                    onSuccess: () => {
                      setSelectedIds(new Set())
                      setConfirmingBulk(false)
                    },
                  })
                }
              >
                {robotTaskText.deleteAction}
              </Button>
            </>
          }
        >
          <p className="text-text-muted">{robotTaskText.bulkDeleteConfirm(selectedIds.size)}</p>
        </Modal>
      )}
    </section>
  )
}

// robot-task-grouping G1 (D-TG-1/2/3/5) — a tabela em GRUPOS COLAPSÁVEIS por
// categoria. Dois layouts que consomem as MESMAS células (§6.1, D-RTT-8): tabela em
// `md+`, cartões abaixo de `md`. Cada categoria é um cabeçalho `<button aria-expanded>`
// com prefixo A./B./C. (visual) + nome + contagem; recolher REMOVE do DOM as tarefas
// do grupo (nunca `display:none`). Estado lembrado por robô (D-TG-4).
function TaskTable({ robotId, tasks, canEdit, isOwner, sel }: { robotId: string; tasks: TaskDTO[]; canEdit: boolean; isOwner: boolean; sel: Selection }) {
  // §6.1 (D-RTT-8) — UM layout por vez (não os dois escondidos por CSS): evita
  // montar duas árvores e mantém o DOM limpo (importa p/ §7.1 e leitores de tela).
  const isDesktop = useMediaQuery('(min-width: 768px)')
  const { isCollapsed, toggle } = useCategoryCollapse(robotId)
  const groups = groupByCategory(tasks)
  // 4.4 (D-RTT-9) — a coluna Ações SAI do DOM para `view`; a de seleção só existe
  // para o dono (G3). O colSpan do cabeçalho de grupo acompanha ambas.
  const cols = 5 + (canEdit ? 1 : 0) + (sel ? 1 : 0)

  if (!isDesktop) {
    return (
      <div className="space-y-3">
        {groups.map((g, i) => {
          const groupCollapsed = isCollapsed(g.cat)
          const rid = `taskgroup-${i}`
          return (
            <section key={g.cat} aria-labelledby={`${rid}-h`}>
              <h2 id={`${rid}-h`}>
                <CategoryToggle
                  letter={groupLetter(i)}
                  cat={g.cat}
                  count={g.tasks.length}
                  collapsed={groupCollapsed}
                  regionId={rid}
                  onToggle={() => toggle(g.cat)}
                  className="w-full px-1 py-2"
                />
              </h2>
              {!groupCollapsed && (
                <div id={rid} className="space-y-3">
                  {g.tasks.map((t) => (
                    <MobileTaskCard
                      key={t.id}
                      robotId={robotId}
                      task={t}
                      canEdit={canEdit}
                      isOwner={isOwner}
                      selectable={!!sel}
                      selected={sel ? sel.selected.has(t.id) : false}
                      onSelect={sel?.toggle}
                    />
                  ))}
                </div>
              )}
            </section>
          )
        })}
      </div>
    )
  }

  return (
    <div className="surface-panel overflow-hidden rounded-lg border">
      <table className="w-full border-collapse text-left">
        <thead>
          <tr className="label-sm text-text-muted">
            {sel && <th className="w-10 px-4 py-2 font-medium"><span className="sr-only">{pagesText.robotTask.select}</span></th>}
            <th className="px-4 py-2 font-medium">{pagesText.robotTask.colTask}</th>
            <th className="px-4 py-2 font-medium">{pagesText.robotTask.colStatus}</th>
            <th className="px-4 py-2 font-medium">{pagesText.robotTask.colProgress}</th>
            <th className="px-4 py-2 font-medium">{pagesText.robotTask.colAssignees}</th>
            <th className="px-4 py-2 font-medium">{pagesText.robotTask.colTrail}</th>
            {canEdit && <th className="px-4 py-2 font-medium">{pagesText.robotTask.colActions}</th>}
          </tr>
        </thead>
        {groups.map((g, i) => {
          const groupCollapsed = isCollapsed(g.cat)
          const rid = `taskgroup-${i}`
          return (
            <tbody key={g.cat} id={rid}>
              <tr>
                <td colSpan={cols} className="bg-accent/5 px-2 py-1">
                  <CategoryToggle
                    letter={groupLetter(i)}
                    cat={g.cat}
                    count={g.tasks.length}
                    collapsed={groupCollapsed}
                    regionId={rid}
                    onToggle={() => toggle(g.cat)}
                    className="px-2 py-1"
                  />
                </td>
              </tr>
              {!groupCollapsed &&
                g.tasks.map((t) => (
                  <TaskRow
                    key={t.id}
                    robotId={robotId}
                    task={t}
                    canEdit={canEdit}
                    isOwner={isOwner}
                    selectable={!!sel}
                    selected={sel ? sel.selected.has(t.id) : false}
                    onSelect={sel?.toggle}
                  />
                ))}
            </tbody>
          )
        })}
      </table>
    </div>
  )
}

// robot-task-grouping G1 — o cabeçalho colapsável de uma categoria (compartilhado
// pelos dois layouts). Chevron gira; `prefers-reduced-motion` já zera a transição no
// CSS global. A contagem é length do grupo (não um % de categoria — D-TG-3).
function CategoryToggle({
  letter,
  cat,
  count,
  collapsed,
  regionId,
  onToggle,
  className = '',
}: {
  letter: string
  cat: string
  count: number
  collapsed: boolean
  regionId: string
  onToggle: () => void
  className?: string
}) {
  return (
    <button
      type="button"
      aria-expanded={!collapsed}
      aria-controls={regionId}
      onClick={onToggle}
      className={
        'panel-header flex min-h-[2rem] w-full items-center gap-2 rounded-md text-left text-text-muted transition-colors hover:text-text-main ' +
        className
      }
    >
      <Icon
        name="chevron-down"
        size="sm"
        className={'shrink-0 transition-transform ' + (collapsed ? '-rotate-90' : '')}
      />
      <span className="tabular text-text-main">{letter}.</span>
      <span className="min-w-0 truncate">{categoryLabel(cat)}</span>
      <span className="label-sm tabular shrink-0 text-text-muted">({count})</span>
    </button>
  )
}

// Status e Progresso interativos (G2); Responsáveis e Trilha (G3); Ações (G4, só
// owner/edit). O pulso aos 100% (§6.3) vive na linha, disparado uma vez e suprimido
// por `prefers-reduced-motion` (o CSS global zera a animação).
//
// §7.1 (render única por mutação) — `memo`: como o React Query faz `structuralSharing`
// por padrão, uma tarefa NÃO alterada mantém a MESMA referência entre refetches;
// então confirmar um avanço numa linha não re-renderiza as linhas vizinhas.
const TaskRow = memo(function TaskRow({ robotId, task, canEdit, isOwner, selectable, selected, onSelect }: { robotId: string; task: TaskDTO; canEdit: boolean; isOwner: boolean; selectable: boolean; selected: boolean; onSelect?: (id: string) => void }) {
  const { pulsing, clear } = useSuccessPulse(task.progress)
  return (
    <tr
      className={'border-t align-top ' + (pulsing ? 'animate-success-pulse' : '') + (selected ? ' bg-accent/5' : '')}
      onAnimationEnd={clear}
    >
      {selectable && (
        <td className="px-4 py-3 align-middle">
          {/* impeccable critique — alvo de luva ≥32px em volta do checkbox de 20px. */}
          <label className="flex min-h-[2rem] min-w-[2rem] cursor-pointer items-center justify-center">
            <input
              type="checkbox"
              className="h-5 w-5 accent-accent"
              checked={selected}
              aria-label={robotTaskText.selectAria(baseTaskLabel(task.desc))}
              onChange={() => onSelect?.(task.id)}
            />
          </label>
        </td>
      )}
      <td className="px-4 py-3">{baseTaskLabel(task.desc)}</td>
      <td className="px-4 py-3 align-middle">
        <StatusCell robotId={robotId} task={task} />
      </td>
      <td className="px-4 py-3 align-middle">
        {/* leitura % + − slider + vivem no AdvanceControls (D-RTT-5) */}
        <AdvanceControls robotId={robotId} taskId={task.id} taskLabel={baseTaskLabel(task.desc)} />
      </td>
      <td className="px-4 py-3">
        <ResponsaveisCell robotId={robotId} task={task} />
      </td>
      <td className="px-4 py-3">
        <TrilhaCell robotId={robotId} task={task} />
      </td>
      {canEdit && (
        <td className="px-4 py-3 align-middle">
          <AcoesCell robotId={robotId} task={task} canDelete={isOwner} />
        </td>
      )}
    </tr>
  )
})

// O cartão mobile (§6.1, D-RTT-8) — as SEIS informações preservadas em linhas
// rotuladas, sem scroll lateral. Reusa as mesmas células da tabela. `memo` pela
// mesma razão da linha (§7.1 — render única por mutação).
const MobileTaskCard = memo(function MobileTaskCard({ robotId, task, canEdit, isOwner, selectable, selected, onSelect }: { robotId: string; task: TaskDTO; canEdit: boolean; isOwner: boolean; selectable: boolean; selected: boolean; onSelect?: (id: string) => void }) {
  const { pulsing, clear } = useSuccessPulse(task.progress)
  return (
    <article
      className={'surface-panel rounded-lg border p-4 ' + (pulsing ? 'animate-success-pulse' : '') + (selected ? ' ring-2 ring-accent' : '')}
      onAnimationEnd={clear}
    >
      <div className="mb-3 flex items-start justify-between gap-2">
        <div className="flex min-w-0 items-start gap-2">
          {selectable && (
            <label className="flex min-h-[2rem] min-w-[2rem] shrink-0 cursor-pointer items-center justify-center">
              <input
                type="checkbox"
                className="h-5 w-5 accent-accent"
                checked={selected}
                aria-label={robotTaskText.selectAria(baseTaskLabel(task.desc))}
                onChange={() => onSelect?.(task.id)}
              />
            </label>
          )}
          <h3 className="min-w-0 font-medium">{baseTaskLabel(task.desc)}</h3>
        </div>
        {canEdit && <AcoesCell robotId={robotId} task={task} canDelete={isOwner} />}
      </div>
      <dl className="space-y-2">
        <CardRow label={pagesText.robotTask.colStatus}>
          <StatusCell robotId={robotId} task={task} />
        </CardRow>
        <CardRow label={pagesText.robotTask.colProgress}>
          <AdvanceControls robotId={robotId} taskId={task.id} taskLabel={baseTaskLabel(task.desc)} />
        </CardRow>
        <CardRow label={pagesText.robotTask.colAssignees}>
          <ResponsaveisCell robotId={robotId} task={task} />
        </CardRow>
        <CardRow label={pagesText.robotTask.colTrail}>
          <TrilhaCell robotId={robotId} task={task} />
        </CardRow>
      </dl>
    </article>
  )
})

function CardRow({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="flex flex-wrap items-center gap-2">
      <dt className="label-sm w-24 shrink-0 text-text-muted">{label}</dt>
      <dd className="min-w-0 flex-1">{children}</dd>
    </div>
  )
}

function TableEmpty({ robotName }: { robotName: string }) {
  return (
    <div className="surface-panel flex flex-col items-center rounded-lg border p-10 text-center">
      <h2 className="panel-header mb-2">{pagesText.robotTask.emptyTitle(robotName)}</h2>
      <p className="max-w-md text-text-muted">{pagesText.robotTask.emptyBody}</p>
    </div>
  )
}

function TableError({ onRetry }: { onRetry: () => void }) {
  return (
    <div className="surface-panel mx-auto mt-6 flex max-w-md flex-col items-center rounded-lg border p-10 text-center">
      <Icon name="alert" size="md" className="mb-2 text-danger-ink" />
      <p className="mb-4 text-text-muted">{pagesText.robotTask.errorBody}</p>
      <Button variant="outline" onClick={onRetry}>
        {pagesText.common.retry}
      </Button>
    </div>
  )
}

function TableSkeleton() {
  return (
    <section className="mx-auto max-w-6xl space-y-6" aria-busy="true" aria-label={pagesText.common.loading}>
      <div className="surface-panel h-8 w-48 animate-pulse rounded-lg border" />
      <div className="surface-panel h-64 animate-pulse rounded-lg border" />
    </section>
  )
}
