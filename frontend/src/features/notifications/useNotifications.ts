import { useMemo } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { notificationsApi, type NotificationDTO } from '@/lib/api/endpoints'
import { qk } from '@/lib/query/keys'
import { useWorkspaceStore } from '@/store/workspaceStore'

// in-app-notifications 6.1 — o hook do centro de notificações sobre React Query
// (D9). Query key `['ws', wsId, 'notifications']`; a contagem de não-lidas é
// DERIVADA da lista (sem estado paralelo). Marcar como lida invalida a key — a
// lista e o badge atualizam sem `window.location.reload()`.
export function useNotifications() {
  const wsId = useWorkspaceStore((s) => s.currentWorkspaceId)
  const queryClient = useQueryClient()
  const key = qk.notifications(wsId ?? '_')

  const query = useQuery({
    queryKey: key,
    queryFn: notificationsApi.list,
    enabled: Boolean(wsId),
  })

  const notifications = useMemo<NotificationDTO[]>(() => query.data ?? [], [query.data])
  const unreadCount = useMemo(() => notifications.filter((n) => !n.read).length, [notifications])

  const invalidate = () => queryClient.invalidateQueries({ queryKey: key })

  const markRead = useMutation({
    mutationFn: (id: string) => notificationsApi.markRead(id),
    onSuccess: invalidate,
  })

  const markAllRead = useMutation({
    mutationFn: () => notificationsApi.markAllRead(),
    onSuccess: invalidate,
  })

  return { notifications, unreadCount, isLoading: query.isLoading, markRead, markAllRead }
}
