import { cn } from '@/lib/utils'
import { Icon } from '@/components/icons/Icon'
import { useMenu } from '@/components/menu/useMenu'
import { PortalMenu, type MenuItem } from '@/components/menu/PortalMenu'
import { notificationPrefsText } from '@/lib/i18n/notifications'
import type { SubscriptionScopeType, SubscriptionState } from '@/lib/api/endpoints'
import { useNotificationSubscriptions, type AncestorScope } from './useNotificationSubscriptions'

// notification-preferences D-P9 — o controle seguir/silenciar de UMA entidade.
// Sino com ESTADO EFETIVO (próprio ou herdado de um ancestral, com a origem no
// rótulo) → PortalMenu com três alvos explícitos (Padrão/Seguir/Silenciar), não um
// toggle que cicla no toque (ambíguo sob luva). Alvo ≥40px, teclado e a11y vêm do
// IconButton/PortalMenu. `ancestry[0]` é a PRÓPRIA entidade (o alvo do controle);
// os demais degraus são só para exibir a herança.
export interface NotificationPreferenceControlProps {
  scope: SubscriptionScopeType
  ancestry: AncestorScope[]
}

export function NotificationPreferenceControl({ scope, ancestry }: NotificationPreferenceControlProps) {
  const menu = useMenu<HTMLButtonElement>()
  const { resolve, setPreference } = useNotificationSubscriptions()
  const own = ancestry[0]
  if (!own || !own.id) return null

  const eff = resolve(ancestry)
  const origin = eff.inherited && eff.source ? eff.source : undefined
  const iconName = eff.state === 'mute' ? 'bell-off' : 'bell'
  const colorClass =
    eff.state === 'follow'
      ? 'text-accent-ink hover:text-accent-ink'
      : eff.state === 'mute'
        ? 'text-text-muted'
        : 'text-text-muted'

  const choose = (state: SubscriptionState | 'default') => {
    if (state === eff.own) return // já é o estado explícito da própria entidade
    setPreference.mutate({ type: own.type, id: own.id, state })
  }

  const withCurrent = (label: string, value: SubscriptionState | 'default') =>
    value === eff.own ? `${label} (atual)` : label

  const items: MenuItem[] = [
    { label: withCurrent(notificationPrefsText.option.default, 'default'), onSelect: () => choose('default') },
    { label: withCurrent(notificationPrefsText.option.follow, 'follow'), onSelect: () => choose('follow') },
    { label: withCurrent(notificationPrefsText.option.mute, 'mute'), onSelect: () => choose('mute') },
  ]

  return (
    <>
      <button
        {...menu.triggerProps}
        type="button"
        aria-label={notificationPrefsText.trigger(scope, eff.state, origin)}
        title={notificationPrefsText.trigger(scope, eff.state, origin)}
        className={cn(
          // alvo ≥40px de luva; foco AA por ring-ring (tokens.json bloco focus)
          'grid h-10 w-10 place-content-center rounded-md transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring',
          colorClass,
        )}
      >
        <Icon name={iconName} size="md" />
      </button>
      <PortalMenu
        anchorRef={menu.anchorRef}
        open={menu.open}
        onClose={menu.close}
        items={items}
        label={notificationPrefsText.menuLabel(scope)}
      />
    </>
  )
}
