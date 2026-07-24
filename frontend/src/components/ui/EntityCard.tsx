import type { ReactNode } from 'react'
import { cn } from '@/lib/utils'
import { Icon } from '@/components/icons/Icon'
import type { IconName } from '@/components/icons/sprite'

// design-system 5.1 (§5.2) — o card de entidade (robô/célula/projeto). MODO DE
// FALHA que este layout existe para evitar: pôr o badge DENTRO do título faz o
// badge empurrar a linha e desalinhar os anéis entre cards da grade. Por isso o
// badge é ELEMENTO IRMÃO do título (em `.card-meta`), o título é `truncate` (uma
// linha só, largura de anel estável), e o anel/rodapé ficam com `mt-auto` num
// container `h-full` — o `offsetTop` do anel é o mesmo com título curto ou longo,
// e dois cards lado a lado têm a mesma altura.
export interface EntityCardProps {
  title: string
  icon?: IconName
  badge?: ReactNode // IRMÃO do título, nunca descendente
  ring?: ReactNode
  footer?: ReactNode
  children?: ReactNode
  className?: string
  onClick?: () => void
}

// Controles internos (Abrir/editar/excluir) que NÃO devem disparar a navegação do
// card ao serem clicados/ativados por teclado.
const INNER_CONTROL = 'button, a, input, select, textarea, [role="button"], label'

export function EntityCard({ title, icon, badge, ring, footer, children, className, onClick }: EntityCardProps) {
  const interactive = !!onClick

  // O card inteiro navega, mas um clique que nasce num controle interno (os botões
  // de editar/excluir do rodapé) NÃO deve navegar — senão excluir uma célula te
  // levaria pra dentro dela. `closest` sobe do alvo até um controle; o `!== card`
  // exclui o PRÓPRIO card (que é `role="button"`) de se auto-detectar como interno.
  const fromInnerControl = (target: EventTarget | null, card: EventTarget) => {
    if (!(target instanceof HTMLElement)) return false
    const el = target.closest(INNER_CONTROL)
    return !!el && el !== card
  }

  const activate = (e: React.MouseEvent) => {
    if (fromInnerControl(e.target, e.currentTarget)) return
    onClick?.()
  }
  const onKeyDown = (e: React.KeyboardEvent) => {
    if ((e.key === 'Enter' || e.key === ' ') && !fromInnerControl(e.target, e.currentTarget)) {
      e.preventDefault()
      onClick?.()
    }
  }

  return (
    <div
      className={cn(
        'surface-panel flex h-full flex-col gap-3 rounded-lg border p-4 shadow-sh-1',
        interactive &&
          'cursor-pointer transition-colors hover:border-accent/40 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent',
        className,
      )}
      onClick={interactive ? activate : undefined}
      onKeyDown={interactive ? onKeyDown : undefined}
      role={interactive ? 'button' : undefined}
      tabIndex={interactive ? 0 : undefined}
      aria-label={interactive ? `Abrir ${title}` : undefined}
    >
      <div className="flex items-start justify-between gap-3">
        <div className="card-meta flex min-w-0 items-center gap-2">
          {icon && (
            <span className="entity-ic grid h-8 w-8 shrink-0 place-content-center rounded-md bg-accent/15 text-accent-ink">
              <Icon name={icon} size="sm" />
            </span>
          )}
          <h3 className="panel-header truncate">{title}</h3>
          {/* badge: IRMÃO do <h3>, não descendente */}
          {badge}
        </div>
        {ring && <div className="shrink-0">{ring}</div>}
      </div>

      {children}

      {footer && <div className="mt-auto flex items-center pt-2">{footer}</div>}
    </div>
  )
}
