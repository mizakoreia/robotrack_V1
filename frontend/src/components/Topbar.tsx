// Topbar com menu condicional
// Exibe itens administrativos apenas quando o usuário está autenticado
// e possui role OG ou Super, evitando falsa percepção de acesso.
import { Link, useLocation } from 'react-router-dom'
import { useAuthStore } from '@/store/authStore'
import { LayoutGrid, MessageSquare, Menu, X, Users as UsersIcon } from 'lucide-react'
import { useEffect, useRef, useState } from 'react'
import type { CSSProperties } from 'react'
import { Tooltip } from '@/components/ui/Tooltip'
/* import { useTheme } from '@/hooks/useTheme' */

export function Topbar() {
  const [open, setOpen] = useState(false)
  /* const { theme } = useTheme() */
  const location = useLocation()
  const { user, isAuthenticated } = useAuthStore()
  const containerRef = useRef<HTMLDivElement | null>(null)

  const t = (user?.user_type || '').toLowerCase()
  const isOG = isAuthenticated && (t.includes('og') || t.includes('super'))
  const items = [
    { type: 'link' as const, path: '/dashboard', label: 'Dashboard', icon: LayoutGrid },
    ...(isOG ? [{ type: 'link' as const, path: '/whatsapp', label: 'WhatsApp', icon: MessageSquare }] : []),
    ...(isOG ? [{ type: 'link' as const, path: '/leads-chat', label: 'Leads', icon: MessageSquare }] : []),
    ...(isOG ? [{ type: 'link' as const, path: '/users', label: 'Usuários', icon: UsersIcon }] : []),
  ]

  useEffect(() => {
    if (!open) return
    const onClick = (e: MouseEvent) => {
      const el = containerRef.current
      if (!el) return
      if (!el.contains(e.target as Node)) {
        setOpen(false)
      }
    }
    document.addEventListener('mousedown', onClick)
    return () => document.removeEventListener('mousedown', onClick)
  }, [open])

  useEffect(() => {
    if (open) setOpen(false)
  }, [location.pathname])

  return (
    <div className="fixed top-6 left-6 z-50" ref={containerRef}>
      <div className="flex flex-col items-center gap-3">
        <button
          aria-label={open ? 'Fechar menu' : 'Abrir menu'}
          onClick={() => setOpen((v) => !v)}
          className="relative flex h-12 w-12 items-center justify-center rounded-full border border-border bg-card text-muted-foreground hover:text-foreground transition-colors"
        >
          {open ? <X className="h-5 w-5" /> : <Menu className="h-5 w-5" />}
        </button>

        <div
          className={`flex flex-col gap-3 ${open ? 'opacity-100 translate-y-0' : 'opacity-0 -translate-y-2 pointer-events-none'} transition-all duration-200`}
        >
          {items.map((item, idx) => {
            const Icon = item.icon
            const isActive = item.type === 'link' && item.path && location.pathname.startsWith(item.path)
            const baseBtn = 'relative flex h-12 w-12 items-center justify-center rounded-full border border-border bg-card text-muted-foreground transition-colors'
            const activeBtn = isActive ? 'bg-primary text-primary-foreground' : 'hover:text-primary hover:border-primary'
            const delayStyle: CSSProperties = { transitionDelay: `${open ? idx * 60 : 0}ms` }
            if (item.type === 'link') {
              return (
                <div key={item.path} style={delayStyle} className={`transition-transform ${open ? 'translate-y-0' : '-translate-y-1'}`}>
                  <div className="relative">
                    {isActive && (
                      <span className="pointer-events-none absolute left-1/2 top-1/2 -z-10 -translate-x-1/2 -translate-y-1/2 h-16 w-16 rounded-full bg-[radial-gradient(circle_at_center,theme(colors.blue.500)_0%,theme(colors.purple.500)_50%,transparent_70%)] blur-xl opacity-70" />
                    )}
                    <Tooltip content={item.label} side="right">
                      <Link to={item.path} className={`${baseBtn} ${activeBtn}`}>
                        <Icon className="h-5 w-5" />
                      </Link>
                    </Tooltip>
                  </div>
                </div>
              )
            }
            return null
          })}
        </div>
      </div>
    </div>
  )
}
