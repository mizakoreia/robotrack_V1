import { cn } from '@/lib/utils'
import { Icon } from '@/components/icons/Icon'
import type { IconName } from '@/components/icons/sprite'

// design-system 6.5 (§5.2) — o indicador de gravação. `aria-live="polite"` para o
// leitor de tela anunciar a mudança. MODO DE FALHA (desonestidade de estado que o
// PRODUCT.md proíbe): dizer "salvo" quando falhou. Por isso o texto de `error`
// afirma que NÃO houve gravação — nunca sugere sucesso.
export type SaveState = 'saving' | 'saved' | 'error'

const MAP: Record<SaveState, { icon: IconName; text: string; ink: string }> = {
  saving: { icon: 'spinner', text: 'Salvando…', ink: 'text-text-muted' },
  saved: { icon: 'check', text: 'Salvo', ink: 'text-success-ink' },
  error: { icon: 'alert', text: 'Erro ao gravar — não salvo', ink: 'text-danger-ink' },
}

export function SaveIndicator({ state, className }: { state: SaveState; className?: string }) {
  const s = MAP[state]
  return (
    <span aria-live="polite" className={cn('label-md inline-flex items-center gap-1', s.ink, className)}>
      <Icon name={s.icon} size="sm" className={state === 'saving' ? 'animate-spin' : undefined} />
      {s.text}
    </span>
  )
}
