import { useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { Icon } from '@/components/icons/Icon'
import { Button } from '@/components/ui/Button'
import { Input } from '@/components/ui/Input'
import { Modal } from '@/components/ui/Modal'
import { Badge } from '@/components/ui/Badge'
import { EntityCard } from '@/components/ui/EntityCard'
import { IconButton } from '@/components/ui/IconButton'
import { ProgressRing } from '@/components/progress/ProgressRing'
import { useProjectOverview, type OverviewCellCard } from '@/features/hierarchy/useOverview'
import { useCreateCell, useRenameCell, useDeleteCell } from '@/features/hierarchy/useHierarchy'
import { LevelHub } from '@/features/hierarchy/LevelHub'
import { BackLink, LevelEmpty, LevelError, LevelSkeleton } from '@/features/hierarchy/LevelChrome'
import { useWorkspaceStore } from '@/store/workspaceStore'
import { hierarchyText } from '@/lib/i18n/hierarchy'

// hierarchy-screens 5.1/5.2/5.5 (§3.3) — a tela de Projeto: hub do projeto + grade
// de cards de Célula (badge N robô(s), anel ponderado, rodapé "Status global /
// Acessar"), ações nova/renomear/excluir célula (invalidando o overview) e voltar.
export function ProjectPage() {
  const { id } = useParams<{ id: string }>()
  const projectId = id ?? null
  const navigate = useNavigate()
  const { data, isLoading, isError, refetch } = useProjectOverview(projectId)
  const role = useWorkspaceStore((s) => s.currentRoleLabel)
  const canEdit = role === 'owner' || role === 'edit'

  const [creating, setCreating] = useState(false)
  const [renaming, setRenaming] = useState<OverviewCellCard | null>(null)
  const [removing, setRemoving] = useState<OverviewCellCard | null>(null)

  const t = hierarchyText.project

  if (isLoading) return <LevelSkeleton />
  if (isError || !data || !projectId) return <LevelError onRetry={() => void refetch()} />

  const empty = data.cells.length === 0

  return (
    <section aria-labelledby="proj-title" className="mx-auto max-w-6xl space-y-6">
      <BackLink label={t.back} onClick={() => navigate('/')} />
      <div className="flex items-center justify-between gap-3">
        <h1 id="proj-title" className="title">
          {data.name}
        </h1>
        {canEdit && !empty && (
          <Button onClick={() => setCreating(true)}>
            <Icon name="plus" size="sm" className="mr-1" />
            {t.newCell}
          </Button>
        )}
      </div>

      {empty ? (
        <LevelEmpty
          title={t.empty.title}
          body={canEdit ? t.empty.body : t.empty.bodyView}
          cta={canEdit ? t.empty.cta : undefined}
          onCta={() => setCreating(true)}
        />
      ) : (
        <>
          <LevelHub
            stats={[
              { label: t.hub.configuredCells, value: String(data.counts.configured_cells) },
              { label: t.hub.analyzedRobots, value: String(data.counts.analyzed_robots) },
              { label: t.hub.completedTasks, value: `${data.raw_completion.completed}/${data.raw_completion.total}` },
            ]}
            percent={data.raw_completion.percent}
            caption={hierarchyText.levelPhysicalCaption(Math.round(data.raw_completion.percent))}
          />
          <p className="label-sm text-text-muted">Anéis: progresso ponderado por peso de tarefa</p>
          <div className="grid items-stretch gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {data.cells.map((cell) => (
              <EntityCard
                key={cell.id}
                title={cell.name}
                icon="list"
                badge={<Badge status="na">{hierarchyText.robotsBadge(cell.robots_count)}</Badge>}
                ring={<ProgressRing value={cell.weighted_progress.value} metric="weighted" size={56} />}
                footer={
                  <div className="flex w-full items-center justify-between">
                    <span className="label-sm text-text-muted">{t.cellFooter}</span>
                    <div className="flex items-center gap-1">
                      {canEdit && (
                        <>
                          <IconButton icon="edit" label={`Renomear ${cell.name}`} size="sm" onClick={() => setRenaming(cell)} />
                          <IconButton icon="trash" label={`Excluir ${cell.name}`} size="sm" onClick={() => setRemoving(cell)} />
                        </>
                      )}
                      <button
                        className="label-md inline-flex min-h-[2rem] items-center font-medium text-accent-ink hover:underline"
                        onClick={() => navigate(`/celula/${cell.id}`)}
                      >
                        {hierarchyText.overview.cardFooterOpen}
                      </button>
                    </div>
                  </div>
                }
              />
            ))}
          </div>
        </>
      )}

      {creating && (
        <CellNameDialog title={t.newCell} projectId={projectId} mode="create" onClose={() => setCreating(false)} />
      )}
      {renaming && (
        <CellNameDialog
          title={t.rename.title}
          projectId={projectId}
          mode="rename"
          cell={renaming}
          onClose={() => setRenaming(null)}
        />
      )}
      {removing && <DeleteCellDialog projectId={projectId} cell={removing} onClose={() => setRemoving(null)} />}
    </section>
  )
}

function CellNameDialog({
  title,
  projectId,
  mode,
  cell,
  onClose,
}: {
  title: string
  projectId: string
  mode: 'create' | 'rename'
  cell?: OverviewCellCard
  onClose: () => void
}) {
  const create = useCreateCell(projectId)
  const rename = useRenameCell(projectId)
  const [name, setName] = useState(cell?.name ?? '')
  const pending = create.isPending || rename.isPending

  function submit(e: React.FormEvent) {
    e.preventDefault()
    const trimmed = name.trim()
    if (!trimmed) return
    if (mode === 'create') create.mutate({ name: trimmed }, { onSuccess: onClose })
    else if (cell) rename.mutate({ id: cell.id, name: trimmed, lockVersion: cell.lock_version }, { onSuccess: onClose })
  }

  return (
    <Modal open onClose={onClose} title={title}>
      <form onSubmit={submit} className="space-y-4">
        <Input value={name} onChange={(e) => setName(e.target.value)} placeholder="Nome da célula" aria-label="Nome da célula" autoFocus />
        <div className="flex justify-end gap-2">
          <Button type="button" variant="ghost" onClick={onClose}>
            Cancelar
          </Button>
          <Button type="submit" disabled={!name.trim() || pending}>
            {mode === 'create' ? 'Criar' : 'Salvar'}
          </Button>
        </div>
      </form>
    </Modal>
  )
}

function DeleteCellDialog({ projectId, cell, onClose }: { projectId: string; cell: OverviewCellCard; onClose: () => void }) {
  const remove = useDeleteCell(projectId)
  const t = hierarchyText.project.remove
  return (
    <Modal open onClose={onClose} title={t.title}>
      <p className="mb-4 text-text-muted">{t.body(cell.name)}</p>
      <div className="flex justify-end gap-2">
        <Button variant="ghost" onClick={onClose}>
          Cancelar
        </Button>
        <Button variant="destructive" disabled={remove.isPending} onClick={() => remove.mutate(cell.id, { onSuccess: onClose })}>
          Excluir
        </Button>
      </div>
    </Modal>
  )
}
