import type { SubscriptionScopeType } from '@/lib/api/endpoints'
import type { NotificationPrefsText } from './notifications'

// internationalization G4 — tradução EN das preferências de notificação. Glossário
// confirmado: "{Project/Cell/Robot} notifications: following/muted/default";
// Seguir→Follow, Silenciar→Mute, Padrão→Default, Seguindo→Following, Silenciado→Muted.
// Mapas próprios de substantivo/origem em inglês (o pt-BR vive em notifications.ts).
const ENTITY_NOUN_EN: Record<SubscriptionScopeType, string> = {
  project: 'Project',
  cell: 'Cell',
  robot: 'Robot',
}

const ENTITY_NOUN_LOWER_EN: Record<SubscriptionScopeType, string> = {
  project: 'project',
  cell: 'cell',
  robot: 'robot',
}

const ENTITY_ORIGIN_EN: Record<SubscriptionScopeType, string> = {
  project: 'by the project',
  cell: 'by the cell',
  robot: 'by the robot',
}

export const notificationPrefsTextEn: NotificationPrefsText = {
  trigger: (scope: SubscriptionScopeType, effective: 'default' | 'follow' | 'mute', origin?: SubscriptionScopeType) => {
    const noun = ENTITY_NOUN_EN[scope]
    if (effective === 'follow') {
      return origin ? `${noun} notifications: following (${ENTITY_ORIGIN_EN[origin]})` : `${noun} notifications: following`
    }
    if (effective === 'mute') {
      return origin
        ? `${noun} notifications: muted (${ENTITY_ORIGIN_EN[origin]})`
        : `${noun} notifications: muted`
    }
    return `${noun} notifications: default`
  },
  menuLabel: (scope: SubscriptionScopeType) => `${ENTITY_NOUN_EN[scope]} notification preference`,
  option: {
    default: 'Default',
    follow: 'Follow',
    mute: 'Mute',
  },
  hint: {
    default: 'You receive updates if you are an assignee.',
    follow: 'Receive updates even without being an assignee.',
    mute: (scope: SubscriptionScopeType) => `Do not receive notifications from this ${ENTITY_NOUN_LOWER_EN[scope]}.`,
  },
  state: {
    follow: 'Following',
    mute: 'Muted',
    default: 'Default',
  },
  inheritedFrom: (origin: SubscriptionScopeType) => ENTITY_ORIGIN_EN[origin],
}
