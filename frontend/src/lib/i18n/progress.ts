// progress-rollup 6.1 (D14/D15) — módulo ÚNICO dos rótulos das duas métricas de
// progresso no frontend, espelho de config/locales/pt-BR.progress.yml. Nenhum
// literal de rótulo vive fora daqui — o sweep progress-label.test.tsx reprova.
//
// As DUAS métricas coexistem de propósito (§2.1 ponderada, §3.2 contagem crua) e
// nenhum número de progresso é renderizado sem dizer qual é (D15).

export type ProgressMetricKind = 'weighted' | 'raw_count'

export const progressText = {
  metrics: {
    weighted: { label: 'Progresso ponderado' },
    raw_count: { label: 'Progresso físico (tarefas concluídas)' },
  },
} as const

export function metricLabel(metric: ProgressMetricKind): string {
  return progressText.metrics[metric].label
}
