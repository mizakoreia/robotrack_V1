import { useRef, useState, type ReactNode } from 'react'
import { cn } from '@/lib/utils'
import { Icon } from '@/components/icons/Icon'
import type { IconName } from '@/components/icons/sprite'
import { useMediaQuery } from '@/lib/useMediaQuery'

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
  // owner-only-card-delete: no TOQUE (mobile), arrastar o card para a esquerda
  // revela "Excluir". É um ATALHO — o caminho acessível (teclado/leitor de tela)
  // continua sendo o `IconButton` do rodapé; por isso o painel revelado é
  // `aria-hidden` e não focável (não duplica o nome acessível — regra G). Tocá-lo
  // abre a confirmação (nunca exclui direto). `undefined` = sem gesto (ex.: não-dono).
  onSwipeDelete?: () => void
}

// Controles internos (Abrir/editar/excluir) que NÃO devem disparar a navegação do
// card ao serem clicados/ativados por teclado.
const INNER_CONTROL = 'button, a, input, select, textarea, [role="button"], label'

const REVEAL_W = 96 // px — largura do painel revelado (alvo de toque ≥ 40px folgado)
const SLOP = 8 // px — limiar para travar a direção (tap vs arrasto; horizontal vs rolagem)

export function EntityCard({
  title,
  icon,
  badge,
  ring,
  footer,
  children,
  className,
  onClick,
  onSwipeDelete,
}: EntityCardProps) {
  const interactive = !!onClick
  // Só no toque/estreito (ponteiro grosso) — progressive enhancement, sem trocar o
  // layout do grid. `fallback: false` para desktop/headless não habilitarem o gesto.
  const coarse = useMediaQuery('(pointer: coarse)', false)
  const reduced = useMediaQuery('(prefers-reduced-motion: reduce)', false)
  const canSwipe = !!onSwipeDelete && coarse

  const [offset, setOffset] = useState(0)
  const [snapping, setSnapping] = useState(false)
  const st = useRef({ startX: 0, startY: 0, base: 0, dir: '' as '' | 'h' | 'v', dragging: false, swiped: false })

  // O card inteiro navega, mas um clique que nasce num controle interno (os botões
  // de editar/excluir do rodapé) NÃO deve navegar — senão excluir uma célula te
  // levaria pra dentro dela. `closest` sobe do alvo até um controle; o `!== card`
  // exclui o PRÓPRIO card (que é `role="button"`) de se auto-detectar como interno.
  const fromInnerControl = (target: EventTarget | null, card: EventTarget) => {
    if (!(target instanceof HTMLElement)) return false
    const el = target.closest(INNER_CONTROL)
    return !!el && el !== card
  }

  const closeSwipe = () => {
    setSnapping(true)
    setOffset(0)
  }

  const activate = (e: React.MouseEvent) => {
    if (fromInnerControl(e.target, e.currentTarget)) return
    // Um clique que fecha um arrasto recém-solto NÃO navega (o navegador dispara um
    // click após o pointerup do swipe).
    if (st.current.swiped) {
      st.current.swiped = false
      return
    }
    // Aberto: um toque no card fecha o painel em vez de navegar.
    if (offset !== 0) {
      closeSwipe()
      return
    }
    onClick?.()
  }
  const onKeyDown = (e: React.KeyboardEvent) => {
    if ((e.key === 'Enter' || e.key === ' ') && !fromInnerControl(e.target, e.currentTarget)) {
      e.preventDefault()
      onClick?.()
    }
  }

  const onPointerDown = (e: React.PointerEvent) => {
    if (!canSwipe) return
    st.current = { startX: e.clientX, startY: e.clientY, base: offset, dir: '', dragging: true, swiped: false }
    setSnapping(false)
  }
  const onPointerMove = (e: React.PointerEvent) => {
    if (!canSwipe || !st.current.dragging) return
    const dx = e.clientX - st.current.startX
    const dy = e.clientY - st.current.startY
    if (st.current.dir === '') {
      if (Math.abs(dx) < SLOP && Math.abs(dy) < SLOP) return
      // Rolagem vertical (dy domina) SOLTA o gesto: a página rola normalmente
      // (touch-action: pan-y). Só o arrasto horizontal move o card.
      st.current.dir = Math.abs(dx) > Math.abs(dy) ? 'h' : 'v'
      if (st.current.dir === 'v') {
        st.current.dragging = false
        return
      }
    }
    if (st.current.dir === 'h') {
      st.current.swiped = true
      // Só para a ESQUERDA (revela à direita); clampado à largura do painel.
      setOffset(Math.min(0, Math.max(-REVEAL_W, st.current.base + dx)))
    }
  }
  const onPointerEnd = () => {
    if (!canSwipe || !st.current.dragging) return
    st.current.dragging = false
    setSnapping(true)
    setOffset((o) => (o <= -REVEAL_W / 2 ? -REVEAL_W : 0))
  }

  const cardClass = cn(
    'surface-panel flex h-full flex-col gap-3 rounded-lg border p-4 shadow-sh-1',
    interactive &&
      'cursor-pointer transition-colors hover:border-accent/40 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent',
    className,
  )

  const inner = (
    <>
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
    </>
  )

  // Caminho comum (sem gesto): estrutura idêntica à de sempre.
  if (!canSwipe) {
    return (
      <div
        className={cardClass}
        onClick={interactive ? activate : undefined}
        onKeyDown={interactive ? onKeyDown : undefined}
        role={interactive ? 'button' : undefined}
        tabIndex={interactive ? 0 : undefined}
        aria-label={interactive ? `Abrir ${title}` : undefined}
      >
        {inner}
      </div>
    )
  }

  // Com gesto: painel "Excluir" atrás (à direita), card opaco por cima deslizando.
  // O painel é `aria-hidden` + não-focável — o caminho acessível é o IconButton do
  // rodapé (o `footer`), que continua no DOM. `touch-action: pan-y` mantém a rolagem.
  return (
    <div className="relative h-full overflow-hidden rounded-lg">
      <div className="absolute inset-y-0 right-0 flex" style={{ width: REVEAL_W }} aria-hidden="true">
        <button
          type="button"
          tabIndex={-1}
          className="flex min-h-[40px] w-full flex-col items-center justify-center gap-1 bg-danger-solid px-2 text-white"
          onClick={() => {
            closeSwipe()
            onSwipeDelete?.()
          }}
        >
          <Icon name="trash" size="sm" />
          <span className="label-sm">Excluir</span>
        </button>
      </div>
      <div
        className={cn(cardClass, 'relative')}
        style={{
          transform: `translateX(${offset}px)`,
          transition: snapping && !reduced ? 'transform 180ms cubic-bezier(0.22,1,0.36,1)' : 'none',
          touchAction: 'pan-y',
        }}
        onClick={interactive ? activate : undefined}
        onKeyDown={interactive ? onKeyDown : undefined}
        onPointerDown={onPointerDown}
        onPointerMove={onPointerMove}
        onPointerUp={onPointerEnd}
        onPointerCancel={onPointerEnd}
        role={interactive ? 'button' : undefined}
        tabIndex={interactive ? 0 : undefined}
        aria-label={interactive ? `Abrir ${title}` : undefined}
      >
        {inner}
      </div>
    </div>
  )
}
