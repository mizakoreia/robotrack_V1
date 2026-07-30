import type { ProgressText } from './progress'

// internationalization G4 — tradução EN dos rótulos das duas métricas (D15).
// Glossário do dono: a métrica ponderada → "Weighted progress"; a métrica de
// contagem crua → "Task completion" (decisão nº 4; NÃO "Physical progress").
// (Os rótulos pt-BR canônicos NÃO são citados aqui — o sweep 6.1 os quer só em
// progress.ts.)
export const progressTextEn: ProgressText = {
  metrics: {
    weighted: { label: 'Weighted progress' },
    raw_count: { label: 'Task completion' },
  },
}
