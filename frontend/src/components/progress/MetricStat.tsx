import { metricLabel, type ProgressMetricKind } from '../../lib/i18n/progress'

// progress-rollup 6.2 (D15) — o número do hub analítico (ex.: "12/40 · 30%"),
// com a métrica declarada. `metric` obrigatória, sem default. O nó acessível
// carrega o rótulo — na Visão Geral, o hub (contagem crua) e o anel do card
// (ponderado) aparecem juntos, cada um rotulado, sem sugerir que um é erro do
// outro. Os rótulos vêm de lib/i18n/progress.ts (nunca literais aqui).
export interface MetricStatProps {
  completed: number
  total: number
  percent: number
  metric: ProgressMetricKind
}

export function MetricStat({ completed, total, percent, metric }: MetricStatProps) {
  const label = metricLabel(metric)

  return (
    <div role="group" aria-label={`${label}: ${completed}/${total} (${percent}%)`} className="inline-flex flex-col">
      <span aria-hidden="true" className="text-lg font-semibold tabular-nums">
        {completed}/{total} · {percent}%
      </span>
      <span aria-hidden="true" className="text-xs text-muted-foreground">
        {label}
      </span>
    </div>
  )
}
