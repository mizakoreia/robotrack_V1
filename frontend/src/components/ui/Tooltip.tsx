import React, { useId, useState } from 'react'

interface TooltipProps {
  content: React.ReactNode
  side?: 'right' | 'left' | 'top' | 'bottom'
  children: React.ReactNode
}

// impeccable-remediation G2 (WCAG 1.4.13) — o tooltip do design-system era
// SÓ-HOVER: o operador de luva/tablet (usuário primário) nunca o disparava, e não
// havia `aria-describedby` nem forma de dispensar. Agora:
//   - abre por hover, por FOCO de teclado e por TOQUE (pointerdown no gatilho);
//   - o conteúdo é associado ao gatilho por `aria-describedby` (o leitor de tela o
//     lê ao focar), num `<span>` de wrapper que recebe `tabIndex=0` se o filho não
//     for naturalmente focável;
//   - `Esc` dispensa (1.4.13 "dismissible") sem tirar o foco do gatilho.
// O `content` precisa ser textual para servir de descrição acessível.
export function Tooltip({ content, side = 'right', children }: TooltipProps) {
  const id = useId()
  const [open, setOpen] = useState(false)

  const pos = {
    right: 'left-full ml-2 top-1/2 -translate-y-1/2',
    left: 'right-full mr-2 top-1/2 -translate-y-1/2',
    top: 'bottom-full mb-2 left-1/2 -translate-x-1/2',
    bottom: 'top-full mt-2 left-1/2 -translate-x-1/2',
  }[side]

  return (
    <span
      className="relative inline-block"
      tabIndex={0}
      aria-describedby={id}
      onMouseEnter={() => setOpen(true)}
      onMouseLeave={() => setOpen(false)}
      onFocus={() => setOpen(true)}
      onBlur={() => setOpen(false)}
      onPointerDown={() => setOpen((v) => !v)}
      onKeyDown={(e) => {
        if (e.key === 'Escape' && open) {
          e.stopPropagation()
          setOpen(false)
        }
      }}
    >
      {children}
      <span
        id={id}
        role="tooltip"
        className={`pointer-events-none absolute ${pos} z-dropdown whitespace-nowrap rounded-md border border-border bg-popover px-2 py-1 text-xs text-popover-foreground shadow-sm transition-opacity duration-150 ${
          open ? 'opacity-100' : 'opacity-0'
        }`}
      >
        {content}
      </span>
    </span>
  )
}
