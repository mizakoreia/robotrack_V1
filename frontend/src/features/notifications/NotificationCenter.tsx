import { useNavigate } from 'react-router-dom'
import { toast } from 'sonner'
import { Button } from '@/components/ui/Button'
import { useNotifications } from './useNotifications'
import { requestOsAlertPermission } from './useOsNotificationAlerts'
import { ctxToPath } from './ctxToPath'
import type { NotificationDTO } from '@/lib/api/endpoints'

// in-app-notifications 6.2 — o centro de notificações. Lista, estado vazio,
// marcar como lida (individual e todas), e a contagem com `aria-live="polite"`
// (o leitor de tela anuncia a mudança). Clicar num item navega para o robô com a
// tarefa destacada; `ctx` quebrado NÃO produz tela branca — mantém aqui com aviso.
export function NotificationCenter() {
  const { notifications, unreadCount, isLoading, markRead, markAllRead } = useNotifications()
  const navigate = useNavigate()

  const open = (n: NotificationDTO) => {
    if (!n.read) markRead.mutate(n.id)
    const path = ctxToPath(n)
    if (path) {
      navigate(path)
    } else {
      toast.warning('Este item não tem um destino válido (o robô pode ter sido excluído).')
    }
  }

  return (
    <section aria-labelledby="notif-center-title" className="space-y-3">
      <header className="flex items-center justify-between">
        <h2 id="notif-center-title" className="panel-header">
          Notificações
          <span aria-live="polite" className="ml-2 text-sm text-text-muted" data-testid="unread-badge">
            {unreadCount > 0 ? `(${unreadCount} não lidas)` : ''}
          </span>
        </h2>
        <div className="flex gap-2">
          {unreadCount > 0 && (
            <Button type="button" variant="ghost" onClick={() => markAllRead.mutate()}>
              Marcar todas como lidas
            </Button>
          )}
          {/* 7.2 — pede permissão SÓ neste clique (nunca no carregamento). */}
          <Button type="button" variant="ghost" onClick={() => void requestOsAlertPermission()}>
            Ativar alertas do sistema
          </Button>
        </div>
      </header>

      {isLoading ? (
        <p className="text-sm text-text-muted">Carregando…</p>
      ) : notifications.length === 0 ? (
        <p className="text-sm text-text-muted" role="status">
          Nenhuma notificação por aqui.
        </p>
      ) : (
        <ul className="space-y-1">
          {notifications.map((n) => (
            <li key={n.id}>
              <button
                type="button"
                onClick={() => open(n)}
                className={`flex w-full items-start gap-3 rounded-md border p-3 text-left ${
                  n.read ? 'opacity-60' : 'bg-accent/5'
                }`}
              >
                {!n.read && <span aria-label="não lida" className="mt-1.5 h-2 w-2 shrink-0 rounded-full bg-accent" />}
                <span className="flex-1 text-sm">
                  <span className="block">{n.msg}</span>
                  <span className="block text-xs text-text-muted">{n.ts_local}</span>
                </span>
              </button>
            </li>
          ))}
        </ul>
      )}
    </section>
  )
}
