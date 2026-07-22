import { useCallback, useEffect, useLayoutEffect, useRef, useState, type RefObject } from 'react'
import { createPortal } from 'react-dom'
import { cn } from '@/lib/utils'
import { getOverlayRoot } from './overlayRoot'
import { computeMenuPosition, type MenuPosition } from './position'

// app-shell-navigation 3.1–3.5 (D-C) — o primitivo de menu suspenso. Renderizado
// em PORTAL na raiz (#rt-overlays), `position: fixed`, na camada `dropdown` da
// escala semântica (design-system). Mede antes de abrir (`visibility: hidden`,
// nunca `display: none`) para decidir subir/descer e alinhamento — nenhum frame
// pinta o menu em posição provisória. Fecha em: clique fora, `Esc` (devolvendo o
// foco ao gatilho), rolagem, resize (com a regra do teclado virtual), escolha de
// item. Teclado: setas com ciclo, Home/End. `role="menu"`/`menuitem`.
export interface MenuItem {
  label: string
  onSelect: () => void
  disabled?: boolean
}

export interface PortalMenuProps {
  anchorRef: RefObject<HTMLElement>
  open: boolean
  onClose: () => void
  items: MenuItem[]
  /** contêiner rolável que fecha o menu ao rolar (além da janela). */
  scrollContainer?: HTMLElement | null
  label?: string
}

export function PortalMenu({ anchorRef, open, onClose, items, scrollContainer, label }: PortalMenuProps) {
  const menuRef = useRef<HTMLDivElement>(null)
  const [pos, setPos] = useState<MenuPosition | null>(null)
  const [active, setActive] = useState(0)
  const openWidth = useRef(0)
  const openHeight = useRef(0)

  // Medição prévia: com o menu montado invisível, lê os retângulos e resolve a
  // posição ANTES do primeiro paint visível.
  useLayoutEffect(() => {
    if (!open) {
      setPos(null)
      return
    }
    const trigger = anchorRef.current?.getBoundingClientRect()
    const menu = menuRef.current?.getBoundingClientRect()
    if (!trigger || !menu) return
    openWidth.current = window.innerWidth
    openHeight.current = window.innerHeight
    setPos(
      computeMenuPosition(
        trigger,
        { width: menu.width, height: menu.height },
        { width: window.innerWidth, height: window.innerHeight },
      ),
    )
    setActive(0)
  }, [open, anchorRef])

  const close = useCallback(() => {
    onClose()
    anchorRef.current?.focus() // devolve o foco ao gatilho
  }, [onClose, anchorRef])

  useEffect(() => {
    if (!open) return

    function onPointerDown(e: PointerEvent) {
      if (menuRef.current?.contains(e.target as Node)) return
      if (anchorRef.current?.contains(e.target as Node)) return
      onClose() // clique fora: NÃO refoca (o gesto pode cair noutro controle)
    }
    function onKey(e: KeyboardEvent) {
      if (e.key === 'Escape') {
        e.stopPropagation() // Esc sobre um modal fecha SÓ o menu
        close()
      }
    }
    function onScroll() {
      onClose()
    }
    function onResize() {
      // teclado virtual: só fecha se a LARGURA mudou ou a altura variou > 120px
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

  const enabledIdx = items.map((it, i) => (it.disabled ? -1 : i)).filter((i) => i >= 0)

  function move(delta: number) {
    if (enabledIdx.length === 0) return
    const cur = enabledIdx.indexOf(active)
    const next = enabledIdx[(cur + delta + enabledIdx.length) % enabledIdx.length]
    setActive(next)
  }

  function onMenuKey(e: React.KeyboardEvent) {
    if (e.key === 'ArrowDown') {
      e.preventDefault()
      move(1)
    } else if (e.key === 'ArrowUp') {
      e.preventDefault()
      move(-1)
    } else if (e.key === 'Home') {
      e.preventDefault()
      setActive(enabledIdx[0] ?? 0)
    } else if (e.key === 'End') {
      e.preventDefault()
      setActive(enabledIdx[enabledIdx.length - 1] ?? 0)
    } else if (e.key === 'Enter' || e.key === ' ') {
      e.preventDefault()
      const it = items[active]
      if (it && !it.disabled) {
        it.onSelect()
        close()
      }
    }
  }

  return createPortal(
    <div
      ref={menuRef}
      role="menu"
      aria-label={label}
      tabIndex={-1}
      onKeyDown={onMenuKey}
      data-placement={pos?.placement}
      data-align={pos?.align}
      style={{
        position: 'fixed',
        top: pos ? pos.top : 0,
        left: pos ? pos.left : 0,
        maxHeight: pos ? pos.maxHeight : undefined,
        overflowY: 'auto',
        visibility: pos ? 'visible' : 'hidden', // nunca display:none
      }}
      className={cn('surface-menu z-dropdown min-w-[10rem] rounded-md border p-1 shadow-sh-2')}
    >
      {items.map((it, i) => (
        <button
          key={it.label}
          type="button"
          role="menuitem"
          disabled={it.disabled}
          data-active={i === active || undefined}
          onClick={() => {
            it.onSelect()
            close()
          }}
          className={cn(
            'label-md block w-full rounded px-2 py-1.5 text-left',
            i === active ? 'bg-accent/15 text-text-main' : 'text-text-muted',
            it.disabled && 'opacity-40',
          )}
        >
          {it.label}
        </button>
      ))}
    </div>,
    getOverlayRoot(),
  )
}
