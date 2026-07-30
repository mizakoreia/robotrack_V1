// notification-preferences D-P9 — os rótulos do controle seguir/silenciar. A
// PALAVRA é spec traduzida, não literal solto no componente (regra da casa). pt-BR.
import type { SubscriptionScopeType } from '@/lib/api/endpoints'

const ENTITY_NOUN: Record<SubscriptionScopeType, string> = {
  project: 'projeto',
  cell: 'célula',
  robot: 'robô',
}

const ENTITY_ORIGIN: Record<SubscriptionScopeType, string> = {
  project: 'pelo projeto',
  cell: 'pela célula',
  robot: 'pelo robô',
}

export const notificationPrefsText = {
  // rótulo acessível do gatilho, com o estado efetivo já resolvido
  trigger: (scope: SubscriptionScopeType, effective: 'default' | 'follow' | 'mute', origin?: SubscriptionScopeType) => {
    const noun = ENTITY_NOUN[scope]
    if (effective === 'follow') {
      return origin ? `Notificações do ${noun}: seguindo (${ENTITY_ORIGIN[origin]})` : `Notificações do ${noun}: seguindo`
    }
    if (effective === 'mute') {
      return origin
        ? `Notificações do ${noun}: silenciado (${ENTITY_ORIGIN[origin]})`
        : `Notificações do ${noun}: silenciado`
    }
    return `Notificações do ${noun}: padrão`
  },
  menuLabel: (scope: SubscriptionScopeType) => `Preferência de notificação do ${ENTITY_NOUN[scope]}`,
  option: {
    default: 'Padrão',
    follow: 'Seguir',
    mute: 'Silenciar',
  },
  // descrição curta abaixo do estado atual (mostrada no gatilho como title)
  hint: {
    default: 'Você recebe se for responsável.',
    follow: 'Receber avanços mesmo sem ser responsável.',
    mute: (scope: SubscriptionScopeType) => `Não receber notificações deste ${ENTITY_NOUN[scope]}.`,
  },
  // texto curto do estado, para chip/tooltip
  state: {
    follow: 'Seguindo',
    mute: 'Silenciado',
    default: 'Padrão',
  },
  inheritedFrom: (origin: SubscriptionScopeType) => ENTITY_ORIGIN[origin],
} as const
