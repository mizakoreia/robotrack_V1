import { useCallback, useEffect, useState } from 'react'
import { keepPreviousData, useQuery } from '@tanstack/react-query'
import { overviewApi } from '../../lib/api/endpoints'
import { qk } from '../../lib/query/keys'
import { useWorkspaceStore } from '../../store/workspaceStore'

export type { SearchResult, SearchResponse } from '../../lib/api/endpoints'

// hierarchy-screens 6.2 (§3.7, D-I) — a busca: debounce 250ms, key ['ws',wsId,
// 'search', q], keepPreviousData (não pisca entre teclas). Só busca com q não-vazio.
export function useHierarchySearch(debouncedQuery: string) {
  const wsId = useWorkspaceStore((s) => s.currentWorkspaceId)
  const q = debouncedQuery.trim()
  return useQuery({
    queryKey: qk.search(wsId ?? '_', q),
    queryFn: () => overviewApi.search(q),
    enabled: Boolean(wsId) && q.length > 0,
    staleTime: 30_000,
    placeholderData: keepPreviousData,
  })
}

// hierarchy-screens 6.2/6.3 — o termo digitado + o termo debounced. `flush` (submit)
// aplica o termo na hora; `clear` restaura a visão. Enter logo após digitar busca UMA
// vez (o timer que dispara depois grava o MESMO termo = sem re-fetch).
export function useSearchQuery(delay = 250) {
  const [query, setQuery] = useState('')
  const [debounced, setDebounced] = useState('')
  useEffect(() => {
    const id = setTimeout(() => setDebounced(query), delay)
    return () => clearTimeout(id)
  }, [query, delay])
  const flush = useCallback(() => setDebounced(query), [query])
  const clear = useCallback(() => {
    setQuery('')
    setDebounced('')
  }, [])
  return { query, setQuery, debounced, flush, clear }
}
