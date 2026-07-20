// Layout component
import { Outlet, useNavigate } from 'react-router-dom'
import { LogOut, Bell, ChevronDown } from 'lucide-react'
import { Topbar } from '@/components/Topbar'
import { toast } from 'sonner'
import { useRef, useState } from 'react'
import { useTheme } from '@/hooks/useTheme'
import { useAuthStore } from '@/store/authStore'

export function Layout() {
  const navigate = useNavigate()
  const APP_NAME = import.meta.env.VITE_APP_NAME || 'robotrack'
  const [hoverOpen, setHoverOpen] = useState({ notifications: false, avatar: false })
  const [, setAvatarImgError] = useState(false)
  const notifTimer = useRef<ReturnType<typeof setTimeout> | null>(null)
  const avatarTimer = useRef<ReturnType<typeof setTimeout> | null>(null)
  const { theme, setTheme } = useTheme()
  const currentUser = useAuthStore((s) => s.user)

  const handleLogout = () => {
    localStorage.removeItem('access_token')
    localStorage.removeItem('refresh_token')
    useAuthStore.getState().logout()
    toast.success('Logout realizado com sucesso!')
    navigate('/login')
  }

  return (
    <div className="h-screen bg-background pl-0 md:pr-8">
      <Topbar />
      <main className="h-full overflow-auto">
        <div className="fixed top-0 left-20 right-0 z-40 bg-transparent md:pr-[4rem] pt-4 mt-[18px] pr-4">
          <div className="flex justify-between items-center mb-2">
            <div className="flex items-center gap-0 text-3xl font-bold select-none -mt-[12px]">
              <div className={`rounded-[500px] px-[4px] pt-0 pb-[7px] flex items-center gap-0 backdrop-blur-sm ${theme === 'dark' ? 'bg-background/30' : 'bg-card/60'}`}>
                <span className="text-blue-500">{'{'}</span>
                <span className="text-foreground">{APP_NAME}</span>
                <span className="text-purple-500">{'}'}</span>
              </div>
            </div>
            <div className="flex items-center gap-3">
              <button
                aria-label="Theme-switch"
                role="switch"
                aria-checked={theme === 'dark'}
                onClick={() => setTheme(theme === 'dark' ? 'light' : 'dark')}
                className={`relative h-6 w-12 rounded-full border border-border transition-colors flex items-center shadow-sm overflow-hidden ${theme === 'dark' ? 'bg-black/40' : 'bg-card'}`}
              >
                <span
                  className={`absolute top-0.5 left-0.5 h-5 w-5 rounded-full transition-transform duration-200 ${theme === 'dark' ? 'translate-x-6 bg-white' : 'translate-x-0 bg-black'}`}
                />
              </button>

              <div
                className="relative"
                onMouseEnter={() => {
                  if (notifTimer.current) clearTimeout(notifTimer.current)
                  setHoverOpen((s) => ({ ...s, notifications: true }))
                }}
                onMouseLeave={() => {
                  if (notifTimer.current) clearTimeout(notifTimer.current)
                  notifTimer.current = setTimeout(() => {
                    setHoverOpen((s) => ({ ...s, notifications: false }))
                  }, 160)
                }}
              >
                <button
                  aria-label="Notificações"
                  className="relative flex h-[38px] w-[38px] items-center justify-center rounded-full border border-border bg-card text-muted-foreground hover:text-foreground hover:bg-accent transition-colors shadow-sm"
                >
                  <Bell className="h-5 w-5" />
                  <span className="absolute -top-0.5 -right-0.5 h-3 w-3 rounded-full bg-red-500 ring-2 ring-card" />
                </button>
                <div
                  onMouseEnter={() => {
                    if (notifTimer.current) clearTimeout(notifTimer.current)
                    setHoverOpen((s) => ({ ...s, notifications: true }))
                  }}
                  onMouseLeave={() => {
                    if (notifTimer.current) clearTimeout(notifTimer.current)
                    notifTimer.current = setTimeout(() => {
                      setHoverOpen((s) => ({ ...s, notifications: false }))
                    }, 160)
                  }}
                  className={`absolute right-0 mt-2 w-80 rounded-lg border border-border bg-card shadow-xl backdrop-blur-sm ${hoverOpen.notifications ? 'block' : 'hidden'} z-50`}
                >
                  <div className="p-3">
                    <div className="mb-2 flex items-center justify-between">
                      <span className="text-sm font-medium">Notificações</span>
                      <span className="text-xs text-muted-foreground">Hoje</span>
                    </div>
                    <ul className="space-y-2">
                      <li className="flex items-start gap-3 rounded-md p-2 hover:bg-accent hover:text-accent-foreground">
                        <span className="mt-1 h-2 w-2 rounded-full bg-red-500" />
                        <div className="flex-1">
                          <div className="text-sm">Pagamento confirmado</div>
                          <div className="text-xs text-muted-foreground">Pedido #1234 foi marcado como pago</div>
                        </div>
                        <span className="text-xs text-muted-foreground">10:24</span>
                      </li>
                      <li className="flex items-start gap-3 rounded-md p-2 hover:bg-accent hover:text-accent-foreground">
                        <span className="mt-1 h-2 w-2 rounded-full bg-red-500" />
                        <div className="flex-1">
                          <div className="text-sm">Nova mensagem WhatsApp</div>
                          <div className="text-xs text-muted-foreground">Cliente João enviou uma mensagem</div>
                        </div>
                        <span className="text-xs text-muted-foreground">09:51</span>
                      </li>
                      <li className="flex items-start gap-3 rounded-md p-2 hover:bg-accent hover:text-accent-foreground">
                        <span className="mt-1 h-2 w-2 rounded-full bg-green-500" />
                        <div className="flex-1">
                          <div className="text-sm">Relatório mensal disponível</div>
                          <div className="text-xs text-muted-foreground">KPIs de novembro estão prontos</div>
                        </div>
                        <span className="text-xs text-muted-foreground">Ontem</span>
                      </li>
                    </ul>
                  </div>
                </div>
              </div>

              <div
                className="relative"
                onMouseEnter={() => {
                  if (avatarTimer.current) clearTimeout(avatarTimer.current)
                  setHoverOpen((s) => ({ ...s, avatar: true }))
                }}
                onMouseLeave={() => {
                  if (avatarTimer.current) clearTimeout(avatarTimer.current)
                  avatarTimer.current = setTimeout(() => {
                    setHoverOpen((s) => ({ ...s, avatar: false }))
                  }, 160)
                }}
              >
                <button
                  aria-label="Menu do usuário"
                  className="relative flex h-[38px] w-[38px] items-center justify-center rounded-full border border-border shadow-sm overflow-hidden p-0"
                >
                  {currentUser?.avatar_url ? (
                    <img
                      src={currentUser.avatar_url}
                      alt="Avatar"
                      className="h-full w-full object-cover"
                      loading="lazy"
                      decoding="async"
                      onError={() => setAvatarImgError(true)}
                    />
                  ) : (
                    <img
                      src={`https://api.dicebear.com/7.x/initials/svg?seed=${encodeURIComponent(currentUser?.name || currentUser?.email || 'User')}`}
                      alt="Avatar"
                      className="h-full w-full object-cover"
                      loading="lazy"
                      decoding="async"
                    />
                  )}
                  <ChevronDown className="pointer-events-none absolute right-1 top-1/2 -translate-y-1/2 h-3 w-3 z-10 text-white drop-shadow-sm" />
                </button>
                <div
                  onMouseEnter={() => {
                    if (avatarTimer.current) clearTimeout(avatarTimer.current)
                    setHoverOpen((s) => ({ ...s, avatar: true }))
                  }}
                  onMouseLeave={() => {
                    if (avatarTimer.current) clearTimeout(avatarTimer.current)
                    avatarTimer.current = setTimeout(() => {
                      setHoverOpen((s) => ({ ...s, avatar: false }))
                    }, 160)
                  }}
                  className={`absolute right-0 mt-2 w-56 rounded-lg border border-border bg-card shadow-xl backdrop-blur-sm ${hoverOpen.avatar ? 'block' : 'hidden'} z-50`}
                >
                  <div className="p-2">
                    <a href="/profile" className="flex items-center gap-2 rounded-md px-3 py-2 text-sm text-foreground hover:bg-accent hover:text-accent-foreground">Perfil</a>
                    <a href="#" className="flex items-center gap-2 rounded-md px-3 py-2 text-sm text-foreground hover:bg-accent hover:text-accent-foreground">Configurações</a>
                    <a href="#" className="flex items-center gap-2 rounded-md px-3 py-2 text-sm text-foreground hover:bg-accent hover:text-accent-foreground">Ajuda</a>
                    <button onClick={handleLogout} className="mt-1 flex w-full items-center gap-2 rounded-md px-3 py-2 text-sm text-muted-foreground hover:bg-accent hover:text-accent-foreground">
                      <LogOut className="h-4 w-4" />
                      <span>Sair</span>
                    </button>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
        <div className="px-4 md:px-8 pt-[82px] pb-8">
          <Outlet />
        </div>
      </main>
    </div>
  )
}
