import { Icon } from '@/components/icons/Icon'
import { useMenu } from '@/components/menu/useMenu'
import { PortalPopover } from '@/components/menu/PortalPopover'
import { useNotifications } from './useNotifications'
import { NotificationCenter } from './NotificationCenter'

// in-app-notifications 6.2 — o PONTO DE ENTRADA do centro de notificações na
// topbar. O `NotificationCenter` estava construído e testado, mas nunca fora
// ligado ao shell atual (`AppShell`); o único caminho ligado era o alerta do SO
// (`useOsNotificationAlerts`). Aqui o sino ocupa o slot `data-slot="notifications"`
// já reservado na topbar, com a contagem de não-lidas como badge, e abre o centro
// num popover ancorado (mesma mecânica do menu da conta: mede antes de pintar,
// fecha em clique-fora/Esc/rolagem, Esc devolve o foco ao sino).
export function NotificationBell() {
  const menu = useMenu()
  const { unreadCount } = useNotifications()

  const label = unreadCount > 0 ? `Notificações (${unreadCount} não lidas)` : 'Notificações'

  return (
    <>
      <button
        {...menu.triggerProps}
        aria-label={label}
        className="relative grid h-9 w-9 place-content-center rounded-md text-text-muted transition-colors hover:text-text-main focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent"
      >
        <Icon name="bell" size="sm" />
        {unreadCount > 0 && (
          <span
            aria-hidden
            data-testid="bell-unread-badge"
            /* impeccable-remediation G1 — `--danger-solid` + branco (5,9:1). Antes:
               `bg-danger` (cheia tingida) + `text-danger-ink` = vermelho-sobre-vermelho
               ~1,30:1, e o número é aria-hidden (só o vidente o consome, e não conseguia). */
            className="absolute -right-0.5 -top-0.5 grid min-w-[1rem] place-content-center rounded-full bg-danger-solid px-1 text-[0.65rem] font-semibold leading-4 text-white"
          >
            {unreadCount > 9 ? '9+' : unreadCount}
          </span>
        )}
      </button>
      <PortalPopover anchorRef={menu.anchorRef} open={menu.open} onClose={menu.close} label="Notificações">
        <div className="w-80 max-w-[90vw] p-3">
          <NotificationCenter />
        </div>
      </PortalPopover>
    </>
  )
}
