import { useCallback, useMemo } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import {
  notificationSubscriptionsApi,
  type NotificationSubscriptionDTO,
  type SubscriptionScopeType,
  type SubscriptionState,
} from '@/lib/api/endpoints'
import { qk } from '@/lib/query/keys'
import { useWorkspaceStore } from '@/store/workspaceStore'

// notification-preferences D-P6/D-P9 — o hook das preferências (seguir/silenciar)
// da própria pessoa, sobre React Query (D9). Query key `['ws', wsId, 'subscriptions']`.
// Mutação de upsert OTIMISTA (molde de useDeleteRobot): atualiza o cache na hora e
// invalida no fim; sem `window.location.reload()`.

export type EffectiveState = 'default' | 'follow' | 'mute'

// Um degrau da ancestralidade da entidade, do MAIS específico ao menos (robô →
// célula → projeto). O resolvedor devolve o primeiro nível com linha própria.
export interface AncestorScope {
  type: SubscriptionScopeType
  id: string
}

export interface EffectiveResult {
  state: EffectiveState
  /** nível de onde o estado veio; null quando é o default (sem linha). */
  source: SubscriptionScopeType | null
  /** true quando o estado vem de um ANCESTRAL, não da própria entidade. */
  inherited: boolean
  /** o estado explícito da PRÓPRIA entidade (o alvo do controle), ou 'default'. */
  own: EffectiveState
}

export function resolveEffective(
  rows: NotificationSubscriptionDTO[],
  ancestry: AncestorScope[],
): EffectiveResult {
  const own = ancestry[0]
  const ownRow = own && rows.find((r) => r.scope_type === own.type && r.scope_id === own.id)
  const ownState: EffectiveState = ownRow ? ownRow.state : 'default'

  for (let i = 0; i < ancestry.length; i += 1) {
    const level = ancestry[i]
    const row = rows.find((r) => r.scope_type === level.type && r.scope_id === level.id)
    if (row) {
      return { state: row.state, source: level.type, inherited: i > 0, own: ownState }
    }
  }
  return { state: 'default', source: null, inherited: false, own: ownState }
}

export function useNotificationSubscriptions() {
  const wsId = useWorkspaceStore((s) => s.currentWorkspaceId)
  const queryClient = useQueryClient()
  const key = qk.subscriptions(wsId ?? '_')

  const query = useQuery({
    queryKey: key,
    queryFn: notificationSubscriptionsApi.list,
    enabled: Boolean(wsId),
  })

  const rows = useMemo<NotificationSubscriptionDTO[]>(() => query.data ?? [], [query.data])

  const setPreference = useMutation({
    mutationFn: ({ type, id, state }: { type: SubscriptionScopeType; id: string; state: SubscriptionState | 'default' }) =>
      notificationSubscriptionsApi.set(type, id, state),
    onMutate: async ({ type, id, state }) => {
      await queryClient.cancelQueries({ queryKey: key })
      const previous = queryClient.getQueryData<NotificationSubscriptionDTO[]>(key) ?? []
      const next = previous.filter((r) => !(r.scope_type === type && r.scope_id === id))
      if (state !== 'default') {
        next.push({
          id: `optimistic-${type}-${id}`,
          scope_type: type,
          scope_id: id,
          state,
          created_at: '',
          updated_at: '',
        })
      }
      queryClient.setQueryData(key, next)
      return { previous }
    },
    onError: (_err, _vars, ctx) => {
      if (ctx?.previous) queryClient.setQueryData(key, ctx.previous)
    },
    onSettled: () => {
      void queryClient.invalidateQueries({ queryKey: key })
    },
  })

  const resolve = useCallback((ancestry: AncestorScope[]) => resolveEffective(rows, ancestry), [rows])

  return { rows, isLoading: query.isLoading, setPreference, resolve }
}
