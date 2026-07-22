import { useEffect } from 'react'
import { useQuery } from '@tanstack/react-query'
import { workspacesApi } from '@/lib/api/endpoints'
import { useWorkspaceStore } from '@/store/workspaceStore'
import { handleAccessRevoked } from './accessRevoked'

// app-shell-navigation 5.7/5.8 (§3.10, D-H) — o carregador do ÍNDICE de workspaces.
// O índice é CACHE DE UI pré-tenant, NUNCA autoridade: por isso a key é
// `['workspaces']` (prefixo não-domínio, fora de `['ws', …]`) e o papel que vem em
// cada item é só rótulo. Dois comportamentos moram aqui:
//   5.7 — se o workspace corrente sumiu do índice recém-carregado, dispara o
//         descarte completo (`handleAccessRevoked`: limpa cache do tenant, volta ao
//         próprio, avisa). Papel local adulterado não muda nada — o servidor decide.
//   5.8 — falha de rede/índice vazio NÃO derruba a casca: a query expõe `isError` e
//         `refetch`, e o contexto degrada para texto estático + "Recarregar".
export function useWorkspaceIndex() {
  const query = useQuery({
    queryKey: ['workspaces'],
    queryFn: () => workspacesApi.list(),
    staleTime: 30_000,
  })

  const currentId = useWorkspaceStore((s) => s.currentWorkspaceId)

  useEffect(() => {
    const data = query.data
    if (!data) return
    useWorkspaceStore
      .getState()
      .setWorkspaces(data.map((w) => ({ id: w.id, name: w.name, role: w.role })))

    // 5.7 — o corrente não está mais no índice: descarte + volta ao próprio.
    if (currentId && !data.some((w) => w.id === currentId)) {
      handleAccessRevoked(currentId)
    }
  }, [query.data, currentId])

  return query
}
