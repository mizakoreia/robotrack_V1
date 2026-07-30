import { useEffect, useRef, useState } from 'react'
import { Link, Outlet, useLocation, useNavigate, useSearchParams } from 'react-router-dom'
import { cn } from '@/lib/utils'
import { useMediaQuery } from '@/lib/useMediaQuery'
import { Icon } from '@/components/icons/Icon'
import { IconButton } from '@/components/ui/IconButton'
import { Button } from '@/components/ui/Button'
import { SaveIndicator, saveStateNeedsAttention } from '@/components/ui/SaveIndicator'
import { PortalMenu } from '@/components/menu/PortalMenu'
import { useMenu } from '@/components/menu/useMenu'
import { LanguageSelect } from '@/components/LanguageSelect'
import { shellText } from '@/lib/i18n/shell'
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
import { NotificationBell } from '@/features/notifications/NotificationBell'
import { performLogout } from '@/lib/auth/session'
import { JoinByCodeDialog } from '@/features/auth/JoinByCodeDialog'
import { SendFeedbackDialog } from '@/features/feedback/SendFeedbackDialog'
import { inviteText } from '@/lib/i18n/invitations'
import { feedbackText } from '@/lib/i18n/feedback'
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

  // join-workspace-by-code — o diálogo de entrada por código é endereçável por
  // `?codigo=1` (espelha o `?convidar=1` da topbar): o item do menu da conta só
  // acrescenta o param, fechar remove. Vive na casca (persistente), disponível em
  // qualquer rota autenticada.
  const [searchParams, setSearchParams] = useSearchParams()
  const joinByCodeOpen = searchParams.get('codigo') === '1'
  const openJoinByCode = () =>
    setSearchParams((prev) => {
      prev.set('codigo', '1')
      return prev
    })
  const closeJoinByCode = () =>
    setSearchParams(
      (prev) => {
        prev.delete('codigo')
        return prev
      },
      { replace: true },
    )

  // send-feedback — o modal de feedback é endereçável por `?feedback=1` (mesmo
  // padrão do `?codigo=1`): o item do menu da conta só acrescenta o param, fechar
  // remove. Vive na casca, disponível em qualquer rota autenticada.
  const feedbackOpen = searchParams.get('feedback') === '1'
  const openFeedback = () =>
    setSearchParams((prev) => {
      prev.set('feedback', '1')
      return prev
    })
  const closeFeedback = () =>
    setSearchParams(
      (prev) => {
        prev.delete('feedback')
        return prev
      },
      { replace: true },
    )
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
        onJoinByCode={openJoinByCode}
        onSendFeedback={openFeedback}
      />

      <div className="flex min-w-0 flex-1 flex-col">
        <Topbar
          role={role}
          saveState={saveState}
          pathname={location.pathname}
          onOpenDrawer={() => setDrawerOpen(true)}
          onNavigate={(p) => navigate(p)}
        />
        {/* aviso de armazenamento bloqueado (offline-pwa 1.3): só em session-only/memory-only */}
        <StorageWarning />
        <main ref={mainRef} className="main flex-1 overflow-y-auto p-4">
          <Outlet />
        </main>
      </div>

      {/* join-workspace-by-code — diálogo de entrada por código (Modal em portal),
          aberto por `?codigo=1` a partir do item do menu da conta. */}
      <JoinByCodeDialog open={joinByCodeOpen} onClose={closeJoinByCode} />

      {/* send-feedback — modal de feedback do beta, aberto por `?feedback=1` a
          partir do item do menu da conta. */}
      <SendFeedbackDialog open={feedbackOpen} onClose={closeFeedback} />
    </div>
  )
}

function Sidebar({
  open,
  onClose,
  pathname,
  user,
  saveState,
  onJoinByCode,
  onSendFeedback,
}: {
  open: boolean
  onClose: () => void
  pathname: string
  user: { name?: string; email?: string } | null
  saveState: ReturnType<typeof selectSaveState>
  onJoinByCode: () => void
  onSendFeedback: () => void
}) {
  const menu = useMenu()
  const navigate = useNavigate()
  const { toggleTheme } = useTheme()
  const name = user?.name?.trim()
  const email = user?.email ?? ''
  const primary = name || email // fallback ao e-mail quando o nome é vazio

  // impeccable-remediation G2 — a gaveta mobile ganha semântica de diálogo modal:
  // abaixo de 768px, quando aberta, o foco entra nela, `Esc` fecha e o Tab fica
  // preso dentro; quando FECHADA, ela sai da ordem de Tab (`inert`) — antes só era
  // empurrada com `-translate-x-full` e seus links/conta seguiam focáveis fora de
  // tela. Acima de 768px a sidebar é permanente e nunca é modal nem inerte.
  const asideRef = useRef<HTMLElement>(null)
  const isDesktop = useMediaQuery('(min-width: 768px)')
  const drawerActive = open && !isDesktop
  const drawerInert = !open && !isDesktop

  useEffect(() => {
    if (!drawerActive) return
    const aside = asideRef.current
    const FOCUSABLE = 'a[href], button, input, select, textarea, [tabindex]:not([tabindex="-1"])'
    aside?.querySelector<HTMLElement>(FOCUSABLE)?.focus()
    function onKey(e: KeyboardEvent) {
      if (e.key === 'Escape') {
        e.stopPropagation()
        onClose()
        return
      }
      if (e.key === 'Tab' && aside) {
        const items = Array.from(aside.querySelectorAll<HTMLElement>(FOCUSABLE))
        if (items.length === 0) return
        const first = items[0]
        const last = items[items.length - 1]
        if (e.shiftKey && document.activeElement === first) {
          e.preventDefault()
          last.focus()
        } else if (!e.shiftKey && document.activeElement === last) {
          e.preventDefault()
          first.focus()
        }
      }
    }
    document.addEventListener('keydown', onKey, true)
    return () => document.removeEventListener('keydown', onKey, true)
  }, [drawerActive, onClose])

  return (
    <>
      {/* backdrop da gaveta (só < md) */}
      {open && <div className="fixed inset-0 z-sidebar bg-black/40 md:hidden" onClick={onClose} aria-hidden="true" />}
      <aside
        ref={asideRef}
        role={drawerActive ? 'dialog' : undefined}
        aria-modal={drawerActive || undefined}
        aria-label={drawerActive ? shellText.drawerNav : undefined}
        {...(drawerInert ? { inert: '' } : {})}
        className={cn(
          'surface-nav z-sidebar flex w-60 shrink-0 flex-col border-r',
          'max-md:fixed max-md:inset-y-0 max-md:left-0 max-md:transition-transform',
          open ? 'max-md:translate-x-0' : 'max-md:-translate-x-full md:translate-x-0',
        )}
      >
        <div className="panel-header px-4 py-4 font-semibold">RoboTrack</div>

        <nav className="flex flex-col gap-1 px-2" aria-label={shellText.navAria}>
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
                {shellText.nav[d.key]}
              </Link>
            )
          })}
        </nav>

        <div className="mt-auto border-t px-3 py-3">
          {/* internationalization D-I7 — o seletor de idioma vive na área da conta,
              sempre acessível. Controle com bandeira (não emoji), aria bilíngue. */}
          <div className="mb-2 flex justify-end">
            <LanguageSelect />
          </div>
          {/* O indicador de gravação só ocupa o canto quando há algo a saber
              (erro/pendente/bloqueado). No repouso ("Salvo") nada é desenhado — sem
              espaçador órfão. Por isso a margem só existe quando ele aparece. */}
          {saveStateNeedsAttention(saveState) && (
            <div className="mb-2">
              <SaveIndicator state={saveState} />
            </div>
          )}
          {/* O nome sozinho não diz o que o botão FAZ (leitor de tela ouviria só
              "Ana Silva, botão"). O rótulo nomeia a ação; o conteúdo visual segue
              sendo o card. */}
          <button
            {...menu.triggerProps}
            aria-label={shellText.account.aria(primary)}
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
          {/* O card de usuário é O menu de conta (padrão de produto: canto inferior
              esquerdo). Antes as ações de conta viviam num SEGUNDO menu, o chevron
              da topbar — dois vocabulários para a mesma coisa. Consolidado aqui:
              destinos de gestão primeiro, preferência, e `Sair` por último. */}
          <PortalMenu
            anchorRef={menu.anchorRef}
            open={menu.open}
            onClose={menu.close}
            label={shellText.account.menuLabel}
            items={[
              // workspace-settings 6.x — a tela existe; os destinos fantasma
              // (/logs, /backup) viraram a própria tela de Configurações.
              { label: shellText.account.settings, onSelect: () => navigate('/configuracoes') },
              { label: shellText.account.team, onSelect: () => navigate('/configuracoes/equipe') },
              // join-workspace-by-code — participar de OUTRO workspace por código.
              // Junto das ações de composição de time; sempre acessível (não
              // depende do seletor de workspace, que só existe com mais de um).
              { label: inviteText.joinByCodeMenu, onSelect: onJoinByCode },
              // send-feedback — canal do beta, sempre disponível no menu da conta
              // (discreto, sem poluir a topbar).
              { label: feedbackText.menuItem, onSelect: onSendFeedback },
              { label: shellText.account.toggleTheme, onSelect: () => toggleTheme() },
              { label: shellText.account.logout, onSelect: () => void performLogout((p) => navigate(p)) },
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
  pathname,
  onOpenDrawer,
  onNavigate,
}: {
  role: string | null
  saveState: ReturnType<typeof selectSaveState>
  pathname: string
  onOpenDrawer: () => void
  onNavigate: (path: string) => void
}) {
  // As ações de conta (tema/sair) moraram aqui num segundo menu; agora vivem no
  // card de usuário da sidebar (canto inferior esquerdo), menu único de conta.
  const canManage = role === 'owner' || role === 'edit'
  const onTeamScreen = pathname.startsWith('/configuracoes/equipe')

  return (
    <header className="surface-panel z-sticky flex h-14 items-center gap-3 border-b px-3">
      <IconButton icon="menu" label={shellText.openMenu} size="sm" className="md:hidden" onClick={onOpenDrawer} />

      {/* contexto do workspace à esquerda (5.2/5.3) */}
      <div className="min-w-0 flex-1">
        <WorkspaceContext />
      </div>

      {/* gaveta fechada: indicador de gravação promovido à topbar (4.5), mas só
          quando há algo a sinalizar (erro/pendente/bloqueado); no repouso não
          ocupa slot. */}
      {saveStateNeedsAttention(saveState) && (
        <div className="md:hidden">
          <SaveIndicator state={saveState} />
        </div>
      )}

      {/* indicador de transporte (7.3): só aparece em degraded/offline */}
      <ConnectionIndicator />

      {/* ajuda-screen — o "?" leva à tela de Ajuda. Único ponto de acesso
          (sempre visível, para operador e dono): não duplica o nome acessível em
          outro controle da casca (regra G). */}
      <IconButton icon="help" label={shellText.help} size="sm" onClick={() => onNavigate('/ajuda')} />

      {/* slot nomeado de notificações — o sino abre o NotificationCenter (6.2) */}
      <div data-slot="notifications" className="flex h-9 w-9 items-center justify-center">
        <NotificationBell />
      </div>

      {/* Convidar pessoa: AÇÃO de gestão, não item escondido num menu. Só para
          quem gerencia (o servidor recusa os demais de qualquer forma — isto é
          não oferecer o que seria negado). Rótulo some abaixo de md; o
          `aria-label` mantém o nome acessível no estado só-ícone.

          ATALHO, não navegação nua: leva à Equipe com `?convidar=1`, que abre o
          formulário — o rótulo promete convidar, então convida (um clique, não
          dois). E o atalho DESAPARECE quando já se está na Equipe: um atalho para
          a tela em que você está é ruído, e era o que punha DOIS botões de mesmo
          nome na mesma tela (o do painel e este). */}
      {canManage && !onTeamScreen && (
        <Button
          type="button"
          variant="outline"
          size="sm"
          aria-label={shellText.invitePerson}
          onClick={() => onNavigate('/configuracoes/equipe?convidar=1')}
        >
          <Icon name="plus" size="sm" />
          <span className="ml-1.5 hidden md:inline">{shellText.invitePerson}</span>
        </Button>
      )}
    </header>
  )
}
