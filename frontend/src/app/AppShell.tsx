import { useEffect, useRef, useState } from 'react'
import { Link, Outlet, useLocation, useNavigate } from 'react-router-dom'
import { cn } from '@/lib/utils'
import { Icon } from '@/components/icons/Icon'
import { IconButton } from '@/components/ui/IconButton'
import { SaveIndicator } from '@/components/ui/SaveIndicator'
import { PortalMenu } from '@/components/menu/PortalMenu'
import { useMenu } from '@/components/menu/useMenu'
import { NAV_DESTINATIONS } from './nav'
import { WorkspaceContext } from './WorkspaceContext'
import { useAuthStore } from '@/store/authStore'
import { useWorkspaceStore } from '@/store/workspaceStore'
import { usePersistenceStore, selectSaveState, mergeSaveState } from '@/store/persistenceStore'
import { useOfflineQueueStore, selectPendingCount, selectHasBlocked } from '@/store/offlineQueueStore'
import { useTheme } from '@/hooks/useTheme'
import { useRealtime } from '@/hooks/useRealtime'
import { useOfflineSync } from '@/hooks/useOfflineSync'
import { useOsNotificationAlerts } from '@/features/notifications/useOsNotificationAlerts'
import { performLogout } from '@/lib/auth/session'
import { registerRevocationNavigator } from '@/lib/workspace/accessRevoked'
import { ConnectionIndicator } from '@/components/realtime/ConnectionIndicator'
import { StorageWarning } from '@/components/StorageWarning'
import { LiveRegions } from '@/components/a11y/LiveRegions'
import { LiveAnnouncer } from '@/components/a11y/LiveAnnouncer'

// app-shell-navigation 4.1–4.5 (§3.10, D-F) — a casca PERSISTENTE. Sidebar de 3
// destinos (ativo por preenchimento tintado + ícone em accent, NUNCA faixa
// lateral), rodapé com indicador de gravação + card de usuário, topbar com
// contexto de workspace à esquerda e menu da conta à direita, e a gaveta abaixo
// de 768px. Navegar entre destinos NÃO remonta sidebar/topbar; só `.main` rola.
export function AppShell() {
  const location = useLocation()
  const navigate = useNavigate()
  const mainRef = useRef<HTMLElement>(null)
  const [drawerOpen, setDrawerOpen] = useState(false)

  const user = useAuthStore((s) => s.user)
  const role = useWorkspaceStore((s) => s.currentRoleLabel)
  const baseSaveState = usePersistenceStore((s) => selectSaveState(s))
  const pendingCount = useOfflineQueueStore(selectPendingCount)
  const hasBlocked = useOfflineQueueStore(selectHasBlocked)
  // offline-pwa 7.3 — o indicador funde gravação online + fila offline.
  const saveState = mergeSaveState(baseSaveState, { pending: pendingCount, blocked: hasBlocked ? 1 : 0 })

  // realtime-collaboration 7.x — o ciclo de vida do tempo real vive na casca
  // persistente (não remonta na navegação entre destinos).
  useRealtime()

  // offline-pwa 6.x — hidrata a fila e orquestra a drenagem sob líder/broadcast.
  useOfflineSync()

  // in-app-notifications 7.x — alerta do SO com marca d'água (não dispara no reload).
  useOsNotificationAlerts()

  // Revogação de acesso (workspace-invitations 5.3): empresta o `navigate` do
  // router à rotina que vive fora do React.
  useEffect(() => {
    registerRevocationNavigator((path) => navigate(path))
    return () => registerRevocationNavigator(null)
  }, [navigate])

  // Rolagem ao topo do CONTEÚDO a cada navegação (o body não rola — só `.main`).
  useEffect(() => {
    mainRef.current?.scrollTo({ top: 0 })
    setDrawerOpen(false) // 4.5 — escolher destino fecha a gaveta
  }, [location.pathname])

  return (
    <div className="flex h-screen overflow-hidden bg-bg-main text-text-main">
      {/* q&a 5.1 — regiões vivas persistentes (montadas vazias) + roteador do
          transporte de tempo real para #rt-status. Incondicionais no shell. */}
      <LiveRegions />
      <LiveAnnouncer />
      <Sidebar
        open={drawerOpen}
        onClose={() => setDrawerOpen(false)}
        pathname={location.pathname}
        user={user}
        saveState={saveState}
      />

      <div className="flex min-w-0 flex-1 flex-col">
        <Topbar
          role={role}
          saveState={saveState}
          onOpenDrawer={() => setDrawerOpen(true)}
          onNavigate={(p) => navigate(p)}
        />
        {/* aviso de armazenamento bloqueado (offline-pwa 1.3): só em session-only/memory-only */}
        <StorageWarning />
        <main ref={mainRef} className="main flex-1 overflow-y-auto p-4">
          <Outlet />
        </main>
      </div>
    </div>
  )
}

function Sidebar({
  open,
  onClose,
  pathname,
  user,
  saveState,
}: {
  open: boolean
  onClose: () => void
  pathname: string
  user: { name?: string; email?: string } | null
  saveState: ReturnType<typeof selectSaveState>
}) {
  const menu = useMenu()
  const navigate = useNavigate()
  const name = user?.name?.trim()
  const email = user?.email ?? ''
  const primary = name || email // fallback ao e-mail quando o nome é vazio

  return (
    <>
      {/* backdrop da gaveta (só < md) */}
      {open && <div className="fixed inset-0 z-sidebar bg-black/40 md:hidden" onClick={onClose} aria-hidden="true" />}
      <aside
        className={cn(
          'surface-nav z-sidebar flex w-60 shrink-0 flex-col border-r',
          'max-md:fixed max-md:inset-y-0 max-md:left-0 max-md:transition-transform',
          open ? 'max-md:translate-x-0' : 'max-md:-translate-x-full md:translate-x-0',
        )}
      >
        <div className="panel-header px-4 py-4 font-semibold">RoboTrack</div>

        <nav className="flex flex-col gap-1 px-2" aria-label="Navegação principal">
          {NAV_DESTINATIONS.map((d) => {
            const active = d.matches(pathname)
            return (
              <Link
                key={d.to}
                to={d.to}
                aria-current={active ? 'page' : undefined}
                className={cn(
                  'label-md flex items-center gap-2 rounded-md px-3 py-2 font-medium',
                  // ativo = PREENCHIMENTO tintado + ícone accent. Sem border-left.
                  active ? 'bg-accent/15 text-accent-ink' : 'text-text-muted hover:text-text-main',
                )}
              >
                <Icon name={d.icon} size="sm" className={active ? 'text-accent' : undefined} />
                {d.label}
              </Link>
            )
          })}
        </nav>

        <div className="mt-auto border-t px-3 py-3">
          <div className="mb-2">
            <SaveIndicator state={saveState} />
          </div>
          <button
            {...menu.triggerProps}
            className="flex w-full items-center gap-2 rounded-md px-2 py-1.5 text-left hover:bg-accent/10"
          >
            <span className="grid h-8 w-8 shrink-0 place-content-center rounded-full bg-accent/15 text-accent-ink">
              {(primary[0] ?? '?').toUpperCase()}
            </span>
            <span className="min-w-0 flex-1">
              <span className="label-md block truncate font-medium text-text-main">{primary}</span>
              {name && <span className="label-sm block truncate text-text-muted">{email}</span>}
            </span>
            <Icon name="chevron-down" size="sm" className="text-text-muted" />
          </button>
          <PortalMenu
            anchorRef={menu.anchorRef}
            open={menu.open}
            onClose={menu.close}
            label="Edição e visualização"
            items={[
              // workspace-settings 6.x — a tela existe; os destinos fantasma
              // (/logs, /backup) viraram a própria tela de Configurações.
              { label: 'Configurações do workspace', onSelect: () => navigate('/configuracoes') },
              { label: 'Equipe e convites', onSelect: () => navigate('/configuracoes/equipe') },
            ]}
          />
        </div>
      </aside>
    </>
  )
}

function Topbar({
  role,
  saveState,
  onOpenDrawer,
  onNavigate,
}: {
  role: string | null
  saveState: ReturnType<typeof selectSaveState>
  onOpenDrawer: () => void
  onNavigate: (path: string) => void
}) {
  const menu = useMenu()
  const { toggleTheme } = useTheme()
  const navigate = useNavigate()
  const canManage = role === 'owner' || role === 'edit'

  const accountItems = [
    ...(canManage ? [{ label: 'Adicionar usuário', onSelect: () => onNavigate('/configuracoes/equipe') }] : []),
    { label: 'Alternar tema', onSelect: () => toggleTheme() },
    { label: 'Sair', onSelect: () => void performLogout((p) => navigate(p)) },
  ]

  return (
    <header className="surface-panel z-sticky flex h-14 items-center gap-3 border-b px-3">
      <IconButton icon="menu" label="Abrir menu" size="sm" className="md:hidden" onClick={onOpenDrawer} />

      {/* contexto do workspace à esquerda (5.2/5.3) */}
      <div className="min-w-0 flex-1">
        <WorkspaceContext />
      </div>

      {/* gaveta fechada: indicador de gravação promovido à topbar (4.5) */}
      <div className="md:hidden">
        <SaveIndicator state={saveState} />
      </div>

      {/* indicador de transporte (7.3): só aparece em degraded/offline */}
      <ConnectionIndicator />

      {/* slot nomeado de notificações — vazio não desloca o layout */}
      <div data-slot="notifications" className="flex h-9 w-9 items-center justify-center" />

      <button {...menu.triggerProps} aria-label="Conta" className="grid h-9 w-9 place-content-center rounded-full bg-accent/15 text-accent-ink">
        <Icon name="chevron-down" size="sm" />
      </button>
      <PortalMenu anchorRef={menu.anchorRef} open={menu.open} onClose={menu.close} label="Conta" items={accountItems} />
    </header>
  )
}
