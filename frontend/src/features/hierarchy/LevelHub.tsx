// hierarchy-screens 5.1/5.3 (§3.3/§3.4, D-B) — o hub analítico dos níveis internos
// (Projeto e Célula). Mesma anatomia da Visão Geral: contagens nomeadas + barra da
// CONTAGEM CRUA (§3.2) com rótulo textual. A barra anima por transform (sem
// relayout). O anel ponderado NÃO aparece aqui — o hub é sempre a métrica crua.
export interface LevelHubStat {
  label: string
  value: string
}

export function LevelHub({
  stats,
  percent,
  caption,
}: {
  stats: LevelHubStat[]
  percent: number
  caption: string
}) {
  const pct = Math.max(0, Math.min(100, Math.round(percent)))
  return (
    <section aria-label="Resumo do nível" className="surface-panel rounded-lg border p-4">
      <div className="grid gap-4" style={{ gridTemplateColumns: `repeat(${stats.length}, minmax(0, 1fr))` }}>
        {stats.map((s) => (
          <div key={s.label} className="flex flex-col">
            <span className="label-sm text-text-muted">{s.label}</span>
            <span className="title tabular">{s.value}</span>
          </div>
        ))}
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
      <p className="label-sm text-text-muted mt-2">{caption}</p>
    </section>
  )
}
