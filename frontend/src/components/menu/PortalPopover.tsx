import { useCallback, useEffect, useLayoutEffect, useRef, useState, type ReactNode, type RefObject } from 'react'
import { createPortal } from 'react-dom'
import { cn } from '@/lib/utils'
import { getOverlayRoot } from './overlayRoot'
import { computeMenuPosition, type MenuPosition } from './position'

// Irmão do PortalMenu para conteúdo RICO (não uma lista de itens): mesma mecânica
// de posicionamento (mede antes de pintar, decide subir/descer e alinhar) e de
// fechamento (clique fora, `Esc` devolvendo o foco ao gatilho, rolagem, resize com
// a regra do teclado virtual), mas renderiza `children` num contêiner
// `role="dialog"`. Mora em components/menu/ porque `createPortal` só é permitido
// aqui (+ Modal) — regra B do convention-sweep. Usado pelo sino de notificações.
export interface PortalPopoverProps {
  anchorRef: RefObject<HTMLElement>
  open: boolean
  onClose: () => void
  children: ReactNode
  scrollContainer?: HTMLElement | null
  label?: string
  className?: string
}

export function PortalPopover({ anchorRef, open, onClose, children, scrollContainer, label, className }: PortalPopoverProps) {
  const panelRef = useRef<HTMLDivElement>(null)
  const [pos, setPos] = useState<MenuPosition | null>(null)
  const openWidth = useRef(0)
  const openHeight = useRef(0)

  useLayoutEffect(() => {
    if (!open) {
      setPos(null)
      return
    }
    const trigger = anchorRef.current?.getBoundingClientRect()
    const panel = panelRef.current?.getBoundingClientRect()
    if (!trigger || !panel) return
    openWidth.current = window.innerWidth
    openHeight.current = window.innerHeight
    setPos(
      computeMenuPosition(
        trigger,
        { width: panel.width, height: panel.height },
        { width: window.innerWidth, height: window.innerHeight },
      ),
    )
    // Leva o foco para dentro do painel (Esc devolve ao gatilho).
    panelRef.current?.focus()
  }, [open, anchorRef])

  const close = useCallback(() => {
    onClose()
    anchorRef.current?.focus()
  }, [onClose, anchorRef])

  useEffect(() => {
    if (!open) return
    function onPointerDown(e: PointerEvent) {
      if (panelRef.current?.contains(e.target as Node)) return
      if (anchorRef.current?.contains(e.target as Node)) return
      onClose() // clique fora: não refoca (o gesto pode cair noutro controle)
    }
    function onKey(e: KeyboardEvent) {
      if (e.key === 'Escape') {
        e.stopPropagation()
        close()
      }
    }
    function onScroll() {
      onClose()
    }
    function onResize() {
      const dw = Math.abs(window.innerWidth - openWidth.current)
      const dh = Math.abs(window.innerHeight - openHeight.current)
      if (dw > 0 || dh > 120) onClose()
    }
    document.addEventListener('pointerdown', onPointerDown, true)
    document.addEventListener('keydown', onKey, true)
    window.addEventListener('scroll', onScroll, true)
    scrollContainer?.addEventListener('scroll', onScroll, true)
    window.addEventListener('resize', onResize)
    return () => {
      document.removeEventListener('pointerdown', onPointerDown, true)
      document.removeEventListener('keydown', onKey, true)
      window.removeEventListener('scroll', onScroll, true)
      scrollContainer?.removeEventListener('scroll', onScroll, true)
      window.removeEventListener('resize', onResize)
    }
  }, [open, onClose, close, anchorRef, scrollContainer])

  if (!open) return null

  return createPortal(
    <div
      ref={panelRef}
      role="dialog"
      aria-label={label}
      aria-modal={false}
      tabIndex={-1}
      data-placement={pos?.placement}
      data-align={pos?.align}
      style={{
        position: 'fixed',
        top: pos ? pos.top : 0,
        left: pos ? pos.left : 0,
        maxHeight: pos ? pos.maxHeight : undefined,
        overflowY: 'auto',
        visibility: pos ? 'visible' : 'hidden', // nunca display:none (mede antes de pintar)
      }}
      className={cn('surface-menu z-dropdown rounded-md border shadow-sh-2 focus-visible:outline-none', className)}
    >
      {children}
    </div>,
    getOverlayRoot(),
  )
}
