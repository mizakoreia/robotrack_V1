import { metricLabel, type ProgressMetricKind } from '../../lib/i18n/progress'

// progress-rollup 6.2 (D15) — o anel de progresso. `metric` é prop OBRIGATÓRIA,
// sem default: `<ProgressRing value={58} />` sem `metric` não compila (o tipo
// exige). O nó acessível expõe o rótulo da métrica E o valor (ex.: "<rótulo>:
// 58%"), nunca só "58". Puramente apresentacional (o dado vem do envelope
// `weighted_progress` da API); a tela é de hierarchy-screens. Rótulos só de
// lib/i18n/progress.ts.
export interface ProgressRingProps {
  value: number
  metric: ProgressMetricKind
  size?: number
}

export function ProgressRing({ value, metric, size = 64 }: ProgressRingProps) {
  const label = metricLabel(metric)
  const dash = `${Math.max(0, Math.min(100, value))}, 100`

  return (
    <div
      role="img"
      aria-label={`${label}: ${value}%`}
      style={{ width: size, height: size }}
      className="relative inline-flex items-center justify-center"
    >
      <svg viewBox="0 0 36 36" className="h-full w-full -rotate-90">
        <circle cx="18" cy="18" r="15.9155" fill="none" stroke="currentColor" strokeOpacity="0.15" strokeWidth="3" />
        <circle
          cx="18"
          cy="18"
          r="15.9155"
          fill="none"
          stroke="currentColor"
          strokeWidth="3"
          strokeDasharray={dash}
          strokeLinecap="round"
        />
      </svg>
      <span aria-hidden="true" className="absolute text-sm font-medium tabular-nums">
        {value}%
      </span>
      <span className="sr-only">{label}</span>
    </div>
  )
}
