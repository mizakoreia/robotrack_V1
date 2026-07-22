import { ProgressRing as BaseProgressRing } from '../ui/ProgressRing'
import { metricLabel, type ProgressMetricKind } from '../../lib/i18n/progress'

// progress-rollup 6.2 (D15) — o anel COM métrica: `metric` obrigatória, sem
// default (`<ProgressRing value={58} />` sem `metric` não compila). Delega o
// visual ao primitivo-base `ui/ProgressRing` (design-system 5.2) — que OMITE o
// path a 0% (nada de ponto arredondado sugerindo avanço) — e só acrescenta o
// rótulo da métrica ao nó acessível ("<rótulo>: 58%", nunca só "58"). Rótulos só
// de lib/i18n/progress.ts.
export interface ProgressRingProps {
  value: number
  metric: ProgressMetricKind
  size?: number
}

export function ProgressRing({ value, metric, size = 64 }: ProgressRingProps) {
  const v = Math.max(0, Math.min(100, Math.round(value)))
  return <BaseProgressRing value={v} size={size} label={`${metricLabel(metric)}: ${v}%`} />
}
