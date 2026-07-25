import { useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { useQueryClient } from '@tanstack/react-query'
import { Icon } from '@/components/icons/Icon'
import { Button } from '@/components/ui/Button'
import { Modal } from '@/components/ui/Modal'
import { Badge } from '@/components/ui/Badge'
import { EntityCard } from '@/components/ui/EntityCard'
import { IconButton } from '@/components/ui/IconButton'
import { ProgressRing } from '@/components/progress/ProgressRing'
import { BatchRobotWizard } from '@/features/tasks/BatchRobotWizard'
import { useCellOverview, type OverviewRobotCard } from '@/features/hierarchy/useOverview'
import { useDeleteRobot } from '@/features/hierarchy/useHierarchy'
import { LevelHub } from '@/features/hierarchy/LevelHub'
import { BackLink, LevelEmpty, LevelError, LevelSkeleton } from '@/features/hierarchy/LevelChrome'
import { useWorkspaceStore } from '@/store/workspaceStore'
import { qk } from '@/lib/query/keys'
import { hierarchyText } from '@/lib/i18n/hierarchy'

// hierarchy-screens 5.3/5.4/5.5 (§3.4) — a tela de Célula: hub da célula + grade de
// cards de Robô (badge = APLICAÇÃO, anel ponderado, rodapé `N tarefas`, "Abrir" →
// tabela do robô), ação "Adicionar robôs" (assistente de robot-tasks) e voltar.
export function CellPage() {
  const { id } = useParams<{ id: string }>()
  const cellId = id ?? null
  const navigate = useNavigate()
  const wsId = useWorkspaceStore((s) => s.currentWorkspaceId)
  const qc = useQueryClient()
  const { data, isLoading, isError, refetch } = useCellOverview(cellId)
  const role = useWorkspaceStore((s) => s.currentRoleLabel)
  const canEdit = role === 'owner' || role === 'edit'
  // owner-only-card-delete: EXCLUIR é só do dono (o servidor confirma com 403).
  const isOwner = role === 'owner'
  const [adding, setAdding] = useState(false)
  const [removing, setRemoving] = useState<OverviewRobotCard | null>(null)

  const t = hierarchyText.cell

  if (isLoading) return <LevelSkeleton />
  if (isError || !data || !cellId) return <LevelError onRetry={() => void refetch()} />

  const empty = data.robots.length === 0
  const closeWizard = () => {
    if (wsId && cellId) void qc.invalidateQueries({ queryKey: qk.cellOverview(wsId, cellId) })
    setAdding(false)
  }

  return (
    <section aria-labelledby="cell-title" className="mx-auto max-w-6xl space-y-6">
      <BackLink label={t.back} onClick={() => navigate(`/projeto/${data.project_id}`)} />
      <div className="flex items-center justify-between gap-3">
        <h1 id="cell-title" className="title">
          {data.name}
        </h1>
        {canEdit && !empty && (
          <Button onClick={() => setAdding(true)}>
            <Icon name="plus" size="sm" className="mr-1" />
            {t.addRobots}
          </Button>
        )}
      </div>

      {empty ? (
        <LevelEmpty
          title={t.empty.title}
          body={canEdit ? t.empty.body : t.empty.bodyView}
          cta={canEdit ? t.empty.cta : undefined}
          onCta={() => setAdding(true)}
        />
      ) : (
        <>
          <LevelHub
            stats={[
              { label: t.hub.configuredRobots, value: String(data.counts.configured_robots) },
              { label: t.hub.completedTasks, value: `${data.raw_completion.completed}/${data.raw_completion.total}` },
            ]}
            percent={data.raw_completion.percent}
            caption={hierarchyText.levelPhysicalCaption(Math.round(data.raw_completion.percent))}
          />
          <p className="label-sm text-text-muted">Anéis: progresso ponderado por peso de tarefa</p>
          <div className="grid items-stretch gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {data.robots.map((robot) => (
              <EntityCard
                key={robot.id}
                title={robot.name}
                icon="file"
                onClick={() => navigate(`/robo/${robot.id}`)}
                // badge = APLICAÇÃO (não a contagem de tarefas), §3.4
                badge={<Badge status="accent">{robot.application}</Badge>}
                ring={<ProgressRing value={robot.weighted_progress.value} metric="weighted" size={56} />}
                onSwipeDelete={isOwner ? () => setRemoving(robot) : undefined}
                footer={
                  <div className="flex w-full items-center justify-between">
                    <span className="label-sm text-text-muted">{hierarchyText.tasksFooter(robot.tasks_count)}</span>
                    {isOwner && (
                      <IconButton icon="trash" label={`Excluir ${robot.name}`} size="sm" onClick={() => setRemoving(robot)} />
                    )}
                  </div>
                }
              />
            ))}
          </div>
        </>
      )}

      {adding && (
        <Modal open onClose={closeWizard} title={t.addRobots}>
          <BatchRobotWizard cellId={cellId} onDone={closeWizard} />
        </Modal>
      )}
      {removing && (
        <DeleteRobotDialog cellId={cellId} projectId={data.project_id} robot={removing} onClose={() => setRemoving(null)} />
      )}
    </section>
  )
}

// owner-only-card-delete: confirma antes de excluir (destrutivo). Excluir um robô
// arquiva suas tarefas (soft-delete cascateia no servidor).
function DeleteRobotDialog({
  cellId,
  projectId,
  robot,
  onClose,
}: {
  cellId: string
  projectId?: string | null
  robot: OverviewRobotCard
  onClose: () => void
}) {
  const remove = useDeleteRobot(cellId, projectId)
  const t = hierarchyText.cell.remove
  return (
    <Modal open onClose={onClose} title={t.title}>
      <p className="mb-4 text-text-muted">{t.body(robot.name)}</p>
      <div className="flex justify-end gap-2">
        <Button variant="ghost" onClick={onClose}>
          Cancelar
        </Button>
        <Button variant="destructive" disabled={remove.isPending} onClick={() => remove.mutate(robot.id, { onSuccess: onClose })}>
          Excluir
        </Button>
      </div>
    </Modal>
  )
}
