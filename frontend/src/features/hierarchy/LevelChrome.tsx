import { Icon } from '@/components/icons/Icon'
import { Button } from '@/components/ui/Button'
import { hierarchyText } from '@/lib/i18n/hierarchy'

// hierarchy-screens 5.5 (§3.3/§3.4) — a moldura compartilhada das telas de nível:
// voltar, estado vazio (com CTA do nível, ausente para papel `view`), erro com
// nova tentativa e o esqueleto de carregamento. Cada nível passa seus próprios
// textos — o vazio de Projeto e o de Célula NÃO são o mesmo "nada aqui".

export function BackLink({ label, onClick }: { label: string; onClick: () => void }) {
  return (
    <button onClick={onClick} className="label-md inline-flex items-center gap-1 text-text-muted hover:text-text-main">
      <Icon name="chevron-down" size="sm" className="rotate-90" />
      {label}
    </button>
  )
}

export function LevelEmpty({
  title,
  body,
  cta,
  onCta,
}: {
  title: string
  body: string
  cta?: string
  onCta?: () => void
}) {
  return (
    <div className="surface-panel flex flex-col items-center rounded-lg border p-10 text-center">
      <h2 className="panel-header mb-2">{title}</h2>
      <p className="mb-4 max-w-md text-text-muted">{body}</p>
      {cta && onCta && (
        <Button onClick={onCta}>
          <Icon name="plus" size="sm" className="mr-1" />
          {cta}
        </Button>
      )}
    </div>
  )
}

export function LevelError({ onRetry }: { onRetry: () => void }) {
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

export function LevelSkeleton() {
  return (
    <section className="mx-auto max-w-6xl space-y-6" aria-busy="true" aria-label="Carregando">
      <div className="surface-panel h-8 w-40 animate-pulse rounded-lg border" />
      <div className="surface-panel h-24 animate-pulse rounded-lg border" />
      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        {[0, 1, 2].map((i) => (
          <div key={i} className="surface-panel h-40 animate-pulse rounded-lg border" />
        ))}
      </div>
    </section>
  )
}
