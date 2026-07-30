// commissioning-report — formatação de APRESENTAÇÃO do relatório. Formatar uma
// data ISO para exibição NÃO é derivar número (D-R1): o valor (`issued_at`,
// `recorded_at`) vem do servidor; aqui só se escolhe como mostrá-lo. Nada de
// `reduce`/`Math.round` (a regra ESLint de features/report/ reprova essas — elas
// seriam recálculo).
// internationalization D-I3 — a data segue o locale corrente (pt-BR / en-GB).
import { localeTag } from '@/lib/i18n/lang'

export function reportDateTime(iso: string | null): string {
  if (!iso) return '—'
  const d = new Date(iso)
  if (Number.isNaN(d.getTime())) return '—'
  return d.toLocaleString(localeTag(), {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  })
}
