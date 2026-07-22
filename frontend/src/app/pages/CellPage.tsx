import { useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { useQueryClient } from '@tanstack/react-query'
import { Icon } from '@/components/icons/Icon'
import { Button } from '@/components/ui/Button'
import { Modal } from '@/components/ui/Modal'
import { Badge } from '@/components/ui/Badge'
import { EntityCard } from '@/components/ui/EntityCard'
import { ProgressRing } from '@/components/progress/ProgressRing'
import { BatchRobotWizard } from '@/features/tasks/BatchRobotWizard'
import { useCellOverview } from '@/features/hierarchy/useOverview'
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
  const [adding, setAdding] = useState(false)

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
                // badge = APLICAÇÃO (não a contagem de tarefas), §3.4
                badge={<Badge status="accent">{robot.application}</Badge>}
                ring={<ProgressRing value={robot.weighted_progress.value} metric="weighted" size={56} />}
                footer={
                  <div className="flex w-full items-center justify-between">
                    <span className="label-sm text-text-muted">{hierarchyText.tasksFooter(robot.tasks_count)}</span>
                    <button
                      className="label-md font-medium text-accent-ink hover:underline"
                      onClick={() => navigate(`/robo/${robot.id}`)}
                    >
                      {t.robotOpen}
                    </button>
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
    </section>
  )
}
