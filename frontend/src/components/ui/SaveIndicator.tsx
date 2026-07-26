import { cn } from '@/lib/utils'
import { Icon } from '@/components/icons/Icon'
import type { IconName } from '@/components/icons/sprite'

// design-system 6.5 (§5.2) — o indicador de gravação. `aria-live="polite"` para o
// leitor de tela anunciar a mudança. MODO DE FALHA (desonestidade de estado que o
// PRODUCT.md proíbe): dizer "salvo" quando falhou. Por isso o texto de `error`
// afirma que NÃO houve gravação — nunca sugere sucesso.
export type SaveState = 'saving' | 'saved' | 'error' | 'pendente' | 'bloqueado'

// save-indicator-quiet — o rodapé só sinaliza o que EXIGE atenção. Os estados de
// repouso/feliz (`saved`, `saving`) não são desenhados: um "Salvo" parado no canto
// é decoração, não informação (PRODUCT.md §5, "cada pixel serve a uma tarefa"), e
// esconder o sucesso NÃO fere o estado honesto (Princípio 2) — ausência nunca
// afirma "salvo"; a exigência é que a FALHA/pendência apareça, e essas seguem
// visíveis. `saving` é transitório e conclui sozinho; o operário não precisa vê-lo.
const ATTENTION: readonly SaveState[] = ['error', 'pendente', 'bloqueado']

/** Verdadeiro só quando o estado carrega algo que o usuário precisa saber/agir. */
export function saveStateNeedsAttention(state: SaveState): boolean {
  return ATTENTION.includes(state)
}

const MAP: Record<SaveState, { icon: IconName; text: string; ink: string }> = {
  saving: { icon: 'spinner', text: 'Salvando…', ink: 'text-text-muted' },
  saved: { icon: 'check', text: 'Salvo', ink: 'text-success-ink' },
  error: { icon: 'alert', text: 'Erro ao gravar — não salvo', ink: 'text-danger-ink' },
  // offline-pwa 7.3 — a fila offline. `pendente`: há alteração guardada esperando
  // a rede; `bloqueado`: uma alteração falhou e travou dependentes (precisa da UI
  // de reconciliação). Nenhum dos dois pode virar "Salvo" — seria desonestidade.
  pendente: { icon: 'info', text: 'Alterações pendentes', ink: 'text-text-muted' },
  bloqueado: { icon: 'alert', text: 'Alterações bloqueadas', ink: 'text-danger-ink' },
}

export function SaveIndicator({ state, className }: { state: SaveState; className?: string }) {
  // Estado de repouso/feliz não ocupa o canto: nada é renderizado (sem placeholder
  // vazio). Quem monta o layout deve usar `saveStateNeedsAttention` para não deixar
  // um espaçador órfão em volta.
  if (!saveStateNeedsAttention(state)) return null
  const s = MAP[state]
  return (
    <span aria-live="polite" className={cn('label-md inline-flex items-center gap-1', s.ink, className)}>
      <Icon name={s.icon} size="sm" className={state === 'saving' ? 'animate-spin' : undefined} />
      {s.text}
    </span>
  )
}
