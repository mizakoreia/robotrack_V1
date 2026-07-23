import { useEffect, useRef } from 'react'
import { useNavigate } from 'react-router-dom'
import { useNotifications } from './useNotifications'
import { ctxToPath } from './ctxToPath'
import { initialAlertState, processNotifications, type AlertDeps, type AlertState } from './osAlerts'

// Ponto ÚNICO de construção de alerta do SO (in-app-notifications 7.1/7.4). É o
// único lugar autorizado a chamar `new Notification(` — a regra de lint
// (no-restricted-syntax) proíbe em qualquer outro arquivo. A marca d'água em
// memória (osAlerts) garante que recarregar com não lidas antigas NÃO dispare.
export function useOsNotificationAlerts(): void {
  const { notifications } = useNotifications()
  const navigate = useNavigate()
  const stateRef = useRef<AlertState>(initialAlertState())

  useEffect(() => {
    if (typeof Notification === 'undefined') return

    const deps: AlertDeps = {
      permission: () => Notification.permission,
      visible: () => document.visibilityState === 'visible',
      fire: (n) => {
        // eslint-disable-next-line no-restricted-syntax
        const osn = new Notification(n.msg, { tag: n.id, body: n.ts_local })
        osn.onclick = () => {
          // 7.4 — foca a aba e navega pelo ctx (o ws-switch entra quando a lista
          // agregar múltiplos workspaces; hoje a lista é escopada ao corrente).
          window.focus()
          const path = ctxToPath(n)
          if (path) navigate(path)
          osn.close()
        }
      },
    }

    stateRef.current = processNotifications(notifications, stateRef.current, deps).state
  }, [notifications, navigate])
}

// 7.2 — pede permissão SÓ neste clique (nunca no carregamento, senão o Chrome
// bloqueia o site por pedido não solicitado).
export function requestOsAlertPermission(): Promise<NotificationPermission> {
  if (typeof Notification === 'undefined') return Promise.resolve('denied')
  return Notification.requestPermission()
}
