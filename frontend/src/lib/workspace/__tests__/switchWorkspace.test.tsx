import { describe, expect, it, vi, beforeEach, afterEach } from 'vitest'
import { render, screen, act, waitFor } from '@testing-library/react'
import { QueryClientProvider, useQuery } from '@tanstack/react-query'
import { queryClient } from '@/lib/queryClient'
import { qk } from '@/lib/query/keys'
import { useWorkspaceStore } from '@/store/workspaceStore'
import { switchWorkspace } from '../switchWorkspace'

// app-shell-navigation 5.5/5.6 (§3.10, D-A) — a barreira CLIENTE contra vazamento
// entre tenants. `switchWorkspace` faz `cancelQueries` → `clear()` → reset → grava
// o novo wsId. Trocar `clear()` por `invalidateQueries` renderiza o dado antigo
// enquanto refaz o fetch (5.5 vermelho); tirar/reordenar o `cancelQueries` deixa a
// resposta atrasada de `betim` escrever cache após a troca (5.6 vermelho).

// Componente que lê os projetos do workspace CORRENTE — a mesma forma de key da
// factory (`['ws', wsId, 'projects']`), que `clear()` apaga por inteiro.
function Projects() {
  const wsId = useWorkspaceStore((s) => s.currentWorkspaceId)
  const { data } = useQuery({
    queryKey: qk.projects(wsId ?? '_'),
    enabled: !!wsId,
    queryFn: async () =>
      wsId === 'camacari' ? [{ id: 'c1', name: 'Célula Norte' }] : [],
  })
  return (
    <ul>
      {(data ?? []).map((p) => (
        <li key={p.id}>{p.name}</li>
      ))}
    </ul>
  )
}

function seedStore() {
  useWorkspaceStore.setState({
    workspaces: [
      { id: 'betim', name: 'Betim', role: 'owner' },
      { id: 'camacari', name: 'Camaçari', role: 'edit' },
    ],
    currentWorkspaceId: 'betim',
    currentRoleLabel: 'owner',
  })
}

beforeEach(() => {
  queryClient.clear()
  seedStore()
})
afterEach(() => {
  queryClient.clear()
})

describe('switchWorkspace (D-A) — barreira de vazamento', () => {
  it('5.5 — cache quente de betim NÃO aparece em nenhum frame após trocar p/ camaçari', async () => {
    // cache quente: os projetos de betim já renderizados (staleTime 30s → sem refetch)
    queryClient.setQueryData(qk.projects('betim'), [
      { id: 'b3', name: 'Linha 3' },
      { id: 'b5', name: 'Linha 5' },
    ])

    render(
      <QueryClientProvider client={queryClient}>
        <Projects />
      </QueryClientProvider>,
    )
    expect(screen.getByText('Linha 3')).toBeInTheDocument()
    expect(screen.getByText('Linha 5')).toBeInTheDocument()

    await act(async () => {
      await switchWorkspace('camacari')
    })

    // asserção central: os textos de betim SUMIRAM e não voltam (clear apagou tudo)
    expect(screen.queryByText('Linha 3')).toBeNull()
    expect(screen.queryByText('Linha 5')).toBeNull()
    await waitFor(() => expect(screen.getByText('Célula Norte')).toBeInTheDocument())
    expect(screen.queryByText('Linha 3')).toBeNull()
    // o cache de betim foi descartado por inteiro
    expect(queryClient.getQueryData(qk.projects('betim'))).toBeUndefined()
  })

  it('5.6 — resposta atrasada de betim não escreve cache após a troca; cancel ANTES de clear', async () => {
    // vi.spyOn preserva a implementação real — só observa a ordem das chamadas.
    const cancelSpy = vi.spyOn(queryClient, 'cancelQueries')
    const clearSpy = vi.spyOn(queryClient, 'clear')

    // query de betim EM VOO: resolve só depois da troca
    let resolveLate: (v: unknown) => void = () => {}
    const late = new Promise((r) => (resolveLate = r))
    // `.catch` engole o CancelledError que `cancelQueries` lança na promise em voo
    queryClient
      .fetchQuery({
        queryKey: qk.projects('betim'),
        queryFn: () => late.then(() => [{ id: 'b9', name: 'Linha 9' }]),
      })
      .catch(() => {})

    await act(async () => {
      await switchWorkspace('camacari')
    })
    await act(async () => {
      resolveLate([{ id: 'b9', name: 'Linha 9' }]) // a resposta atrasada chega agora
      await Promise.resolve()
    })

    expect(cancelSpy).toHaveBeenCalled()
    expect(clearSpy).toHaveBeenCalled()
    // cancel ANTES de clear — a inversão faria a resposta atrasada escrever cache
    expect(cancelSpy.mock.invocationCallOrder[0]).toBeLessThan(clearSpy.mock.invocationCallOrder[0])
    // e o cache de betim segue vazio: a resposta atrasada não escreveu nada
    expect(queryClient.getQueryData(qk.projects('betim'))).toBeUndefined()

    cancelSpy.mockRestore()
    clearSpy.mockRestore()
  })

  it('escolher o workspace já corrente não tem efeito (sem cancel, sem clear)', async () => {
    const cancelSpy = vi.spyOn(queryClient, 'cancelQueries')
    const clearSpy = vi.spyOn(queryClient, 'clear')
    await act(async () => {
      await switchWorkspace('betim') // já é o corrente
    })
    expect(cancelSpy).not.toHaveBeenCalled()
    expect(clearSpy).not.toHaveBeenCalled()
    expect(useWorkspaceStore.getState().currentWorkspaceId).toBe('betim')
    cancelSpy.mockRestore()
    clearSpy.mockRestore()
  })
})
