import type { NotificationDTO } from '@/lib/api/endpoints'

// Alerta do SO — o núcleo (in-app-notifications 7.1/7.3 / D-N8). "Novo" é uma
// MARCA D'ÁGUA em memória (o maior recorded_at visto), NÃO `read = false`. A
// PRIMEIRA resposta da sessão só INICIALIZA a marca — dispara ZERO alertas. Isso
// mata o modo de falha desta capacidade: recarregar com 10 (ou 40) não lidas de
// ontem NÃO deve soltar uma saraivada de alertas do SO. Só disparam notificações
// com recorded_at > marca chegando DEPOIS (evento ao vivo / polling), uma vez por
// id (dedup), e só quando a aba está OCULTA (visível = o usuário já está vendo).

export interface AlertState {
  initialized: boolean
  watermark: string // maior recorded_at visto
  alerted: Set<string> // ids já alertados (dedup)
}

export const initialAlertState = (): AlertState => ({ initialized: false, watermark: '', alerted: new Set() })

export interface AlertDeps {
  permission: () => NotificationPermission
  visible: () => boolean
  fire: (n: NotificationDTO) => void // constrói o Notification do SO
}

function maxRecordedAt(list: NotificationDTO[]): string {
  return list.reduce((max, n) => (n.recorded_at > max ? n.recorded_at : max), '')
}

// Processa uma lista contra o estado; devolve o novo estado e quantos alertas
// foram DISPARADOS (0 na 1ª resposta, e 0 quando suprimido por permissão/visível).
export function processNotifications(
  notifications: NotificationDTO[],
  state: AlertState,
  deps: AlertDeps,
): { state: AlertState; fired: number } {
  // Primeira resposta da sessão: só inicializa a marca e o conjunto visto.
  if (!state.initialized) {
    return {
      state: { initialized: true, watermark: maxRecordedAt(notifications), alerted: new Set(notifications.map((n) => n.id)) },
      fired: 0,
    }
  }

  const alerted = new Set(state.alerted)
  let watermark = state.watermark
  let fired = 0

  for (const n of notifications) {
    if (n.read) continue
    if (n.recorded_at <= state.watermark) continue // não é mais novo que a marca
    if (alerted.has(n.id)) continue // dedup: já alertado (ex.: evento + refetch)

    alerted.add(n.id)
    if (n.recorded_at > watermark) watermark = n.recorded_at

    // Gate de disparo: permissão concedida E aba OCULTA. Suprimido ainda conta
    // como "visto" (marca avança), para não disparar depois fora de hora.
    if (deps.permission() === 'granted' && !deps.visible()) {
      deps.fire(n)
      fired += 1
    }
  }

  return { state: { initialized: true, watermark, alerted }, fired }
}
