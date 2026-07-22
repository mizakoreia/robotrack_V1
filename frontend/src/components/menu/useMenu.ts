import { useCallback, useRef, useState } from 'react'

// app-shell-navigation 3.5 (D-C) — o gatilho correto por construção: espalhe
// `triggerProps` no botão e passe `anchorRef`/`open`/`onClose` ao <PortalMenu>.
// `aria-haspopup="menu"` e `aria-expanded` refletem o estado REAL do menu.
export function useMenu<T extends HTMLElement = HTMLButtonElement>() {
  const anchorRef = useRef<T>(null)
  const [open, setOpen] = useState(false)
  const close = useCallback(() => setOpen(false), [])

  const triggerProps = {
    ref: anchorRef,
    'aria-haspopup': 'menu' as const,
    'aria-expanded': open,
    onClick: () => setOpen((o) => !o),
  }

  return { anchorRef, open, setOpen, close, triggerProps }
}
