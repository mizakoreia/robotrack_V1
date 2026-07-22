import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useQueryClient } from '@tanstack/react-query'
import { Icon } from '@/components/icons/Icon'
import { Button } from '@/components/ui/Button'
import { Input } from '@/components/ui/Input'
import { Modal } from '@/components/ui/Modal'
import { Badge } from '@/components/ui/Badge'
import { EntityCard } from '@/components/ui/EntityCard'
import { ProgressRing } from '@/components/progress/ProgressRing'
import {
  useWorkspaceOverview,
  type OverviewProjectCard,
  type RawCompletionEnvelope,
  type WorkspaceOverviewDTO,
} from '@/features/hierarchy/useOverview'
import { useCreateProject } from '@/features/hierarchy/useHierarchy'
import { useWorkspaceStore } from '@/store/workspaceStore'
import { qk } from '@/lib/query/keys'
import { hierarchyText } from '@/lib/i18n/hierarchy'

// hierarchy-screens 4.1–4.6 (§3.2, D-A, D-G, D-H) — a tela Visão Geral. As DUAS
// métricas na mesma dobra: o hub usa a CONTAGEM CRUA (§3.2, "de progresso físico
// global") e o anel de cada card usa o PONDERADO (§2.1 — o rótulo acessível vem de
// lib/i18n/progress via components/progress/ProgressRing). Elas divergem de
// propósito (D15) e nenhuma é lida da outra — o tipo separa `raw_completion` de
// `weighted_progress`, então confundir os dois nem compila.
export function OverviewPage() {
  const { data, isLoading, isError, refetch } = useWorkspaceOverview()
  const role = useWorkspaceStore((s) => s.currentRoleLabel)
  const canCreate = role === 'owner' || role === 'edit' // §4.1 — view não cria
  const navigate = useNavigate()
  const [creating, setCreating] = useState(false)

  if (isLoading) return <OverviewSkeleton />
  if (isError || !data) return <OverviewError onRetry={() => void refetch()} />

  const empty = data.projects.length === 0

  return (
    <section aria-labelledby="ov-title" className="mx-auto max-w-6xl space-y-6">
      <div className="flex items-center justify-between gap-3">
        <h1 id="ov-title" className="title">
          Visão Geral
        </h1>
        {canCreate && !empty && (
          <Button onClick={() => setCreating(true)}>
            <Icon name="plus" size="sm" className="mr-1" />
            {hierarchyText.overview.empty.cta}
          </Button>
        )}
      </div>

      {empty ? (
        <OverviewEmpty canCreate={canCreate} onCreate={() => setCreating(true)} />
      ) : (
        <>
          <OverviewHub counts={data.counts} raw={data.raw_completion} />
          {/* legenda única da grade (D-B): o anel não repete rótulo por card */}
          <p className="label-sm text-text-muted">Anéis: progresso ponderado por peso de tarefa</p>
          <div className="grid items-stretch gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {data.projects.map((p) => (
              <ProjectCard key={p.id} project={p} onOpen={() => navigate(`/projeto/${p.id}`)} />
            ))}
          </div>
        </>
      )}

      <NewProjectDialog open={creating} onClose={() => setCreating(false)} />
    </section>
  )
}

function OverviewHub({
  counts,
  raw,
}: {
  counts: WorkspaceOverviewDTO['counts']
  raw: RawCompletionEnvelope
}) {
  const t = hierarchyText.overview.hub
  const pct = Math.max(0, Math.min(100, Math.round(raw.percent)))
  return (
    <section aria-label="Resumo do workspace" className="surface-panel rounded-lg border p-4">
      <div className="grid grid-cols-3 gap-4">
        <Stat label={t.activeProjects} value={String(counts.active_projects)} />
        <Stat label={t.analyzedRobots} value={String(counts.analyzed_robots)} />
        {/* contagem crua §3.2: "1/4" */}
        <Stat label={t.completedTasks} value={`${raw.completed}/${raw.total}`} />
      </div>
      <div
        role="progressbar"
        aria-valuenow={pct}
        aria-valuemin={0}
        aria-valuemax={100}
        className="bg-track mt-4 h-2 w-full overflow-hidden rounded-pill"
      >
        <div
          className="bg-accent-solid h-full w-full origin-left transition-transform"
          style={{ transform: `scaleX(${pct / 100})` }}
        />
      </div>
      {/* rótulo contextual (D-B): "25% de progresso físico global" */}
      <p className="label-sm text-text-muted mt-2">{t.physicalCaption(pct)}</p>
    </section>
  )
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex flex-col">
      <span className="label-sm text-text-muted">{label}</span>
      <span className="title tabular">{value}</span>
    </div>
  )
}

function ProjectCard({ project, onOpen }: { project: OverviewProjectCard; onOpen: () => void }) {
  const t = hierarchyText.overview
  return (
    <EntityCard
      title={project.name}
      icon="file"
      badge={<Badge status="na">{hierarchyText.cellsBadge(project.cells_count)}</Badge>}
      ring={<ProgressRing value={project.weighted_progress.value} metric="weighted" size={56} />}
      footer={
        <div className="flex w-full items-center justify-between">
          <span className="label-sm text-text-muted">{t.cardFooterMacro}</span>
          <button className="label-md font-medium text-accent-ink hover:underline" onClick={onOpen}>
            {t.cardFooterOpen}
          </button>
        </div>
      }
    />
  )
}

function OverviewEmpty({ canCreate, onCreate }: { canCreate: boolean; onCreate: () => void }) {
  const t = hierarchyText.overview.empty
  return (
    <div className="surface-panel flex flex-col items-center rounded-lg border p-10 text-center">
      <h2 className="panel-header mb-2">{t.title}</h2>
      <p className="mb-4 max-w-md text-text-muted">{canCreate ? t.body : t.bodyView}</p>
      {canCreate && (
        <Button onClick={onCreate}>
          <Icon name="plus" size="sm" className="mr-1" />
          {t.cta}
        </Button>
      )}
    </div>
  )
}

function OverviewError({ onRetry }: { onRetry: () => void }) {
  const t = hierarchyText.overview.error
  return (
    <div className="surface-panel mx-auto mt-6 flex max-w-md flex-col items-center rounded-lg border p-10 text-center">
      <Icon name="alert" size="md" className="mb-2 text-danger-ink" />
      <p className="mb-4 text-text-muted">{t.body}</p>
      <Button variant="outline" onClick={onRetry}>
        {t.retry}
      </Button>
    </div>
  )
}

function OverviewSkeleton() {
  return (
    <section className="mx-auto max-w-6xl space-y-6" aria-busy="true" aria-label="Carregando">
      <div className="surface-panel h-24 animate-pulse rounded-lg border" />
      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        {[0, 1, 2].map((i) => (
          <div key={i} className="surface-panel h-40 animate-pulse rounded-lg border" />
        ))}
      </div>
    </section>
  )
}

function NewProjectDialog({ open, onClose }: { open: boolean; onClose: () => void }) {
  const wsId = useWorkspaceStore((s) => s.currentWorkspaceId)
  const qc = useQueryClient()
  const create = useCreateProject()
  const [name, setName] = useState('')

  function submit(e: React.FormEvent) {
    e.preventDefault()
    const trimmed = name.trim()
    if (!trimmed) return
    create.mutate(
      { name: trimmed },
      {
        onSuccess: () => {
          // o overview é uma projeção agregada — invalida a key da tela também
          if (wsId) void qc.invalidateQueries({ queryKey: qk.overview(wsId) })
          setName('')
          onClose()
        },
      },
    )
  }

  return (
    <Modal open={open} onClose={onClose} title={hierarchyText.overview.empty.cta}>
      <form onSubmit={submit} className="space-y-4">
        <Input
          value={name}
          onChange={(e) => setName(e.target.value)}
          placeholder="Nome do projeto"
          aria-label="Nome do projeto"
          autoFocus
        />
        <div className="flex justify-end gap-2">
          <Button type="button" variant="ghost" onClick={onClose}>
            Cancelar
          </Button>
          <Button type="submit" disabled={!name.trim() || create.isPending}>
            Criar
          </Button>
        </div>
      </form>
    </Modal>
  )
}
