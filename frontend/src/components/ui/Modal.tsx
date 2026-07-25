import { useEffect, useRef, type ReactNode } from 'react'
import { createPortal } from 'react-dom'
import { cn } from '@/lib/utils'
import { IconButton } from './IconButton'

// design-system 6.4 (§5.2) — o Modal no nível `--z-modal`, com focus trap e Esc
// que DEVOLVE o foco ao gatilho. MODO DE FALHA: após abrir pelo botão "Registrar
// avanço" e pressionar Esc, o foco cai no `<body>` e quem navega por teclado
// recomeça do topo. Por isso capturamos o `activeElement` na abertura e o
// refocamos no fechamento. `aria-modal` sinaliza o resto da árvore como inerte
// para leitores de tela; o Tab é preso dentro do diálogo.
export interface ModalProps {
  open: boolean
  onClose: () => void
  title: string
  children?: ReactNode
  footer?: ReactNode
}

const FOCUSABLE = 'button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])'

export function Modal({ open, onClose, title, children, footer }: ModalProps) {
  const dialogRef = useRef<HTMLDivElement>(null)
  const triggerRef = useRef<HTMLElement | null>(null)

  useEffect(() => {
    if (!open) return
    triggerRef.current = document.activeElement as HTMLElement
    const dialog = dialogRef.current
    const first = dialog?.querySelector<HTMLElement>(FOCUSABLE)
    ;(first ?? dialog)?.focus()

    function onKey(e: KeyboardEvent) {
      if (e.key === 'Escape') {
        e.stopPropagation()
        onClose()
        return
      }
      if (e.key === 'Tab' && dialog) {
        const items = Array.from(dialog.querySelectorAll<HTMLElement>(FOCUSABLE))
        if (items.length === 0) {
          e.preventDefault()
          return
        }
        const firstEl = items[0]
        const lastEl = items[items.length - 1]
        if (e.shiftKey && document.activeElement === firstEl) {
          e.preventDefault()
          lastEl.focus()
        } else if (!e.shiftKey && document.activeElement === lastEl) {
          e.preventDefault()
          firstEl.focus()
        }
      }
    }

    document.addEventListener('keydown', onKey, true)
    // impeccable-remediation G2 — scroll-lock do body: com o modal aberto no
    // mobile, a página rolava atrás do overlay. Guarda o overflow anterior e o
    // restaura no fechamento (sem assumir que era `visible`).
    const prevOverflow = document.body.style.overflow
    document.body.style.overflow = 'hidden'
    return () => {
      document.removeEventListener('keydown', onKey, true)
      document.body.style.overflow = prevOverflow
      triggerRef.current?.focus?.() // devolve o foco ao gatilho
    }
  }, [open, onClose])

  if (!open) return null

  return createPortal(
    <div className="fixed inset-0 z-modal flex items-center justify-center p-4">
      <div className="absolute inset-0 bg-black/50 backdrop-blur-sm" onClick={onClose} aria-hidden="true" />
      <div
        ref={dialogRef}
        role="dialog"
        aria-modal="true"
        aria-label={title}
        tabIndex={-1}
        // impeccable-remediation G2 — `max-h-[90vh]` + coluna flex: o corpo rola
        // internamente (não estoura o viewport), com a barra e o rodapé fixos.
        className={cn('surface-menu relative flex max-h-[90vh] w-full max-w-md flex-col rounded-lg border p-0 shadow-sh-3')}
      >
        <div className="modal-bar flex shrink-0 items-center justify-between border-b px-4 py-3">
          <h2 className="modal-title">{title}</h2>
          {/* impeccable-remediation G2 — × com alvo de toque (era glifo cru). */}
          <IconButton icon="close" label="Fechar" size="sm" onClick={onClose} className="-mr-2" />
        </div>
        <div className="overflow-y-auto px-4 py-4">{children}</div>
        {footer && <div className="modal-foot flex shrink-0 items-center justify-end gap-2 border-t px-4 py-3">{footer}</div>}
      </div>
    </div>,
    document.body,
  )
}
