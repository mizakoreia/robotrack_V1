import { queryClient } from '../queryClient'
import { useWorkspaceStore } from '../../store/workspaceStore'
import { purgeQueryCache } from '../query/persist'

// app-shell-navigation 5.4 (§3.10, D-A) — a troca de workspace é a ÚNICA barreira
// CLIENTE contra vazamento entre tenants. Ordem FIXA e obrigatória:
//   1. cancelQueries  — a resposta atrasada de W-A não escreve cache após a troca
//   2. clear()        — cache INTEIRO, não invalidação seletiva (que renderizaria
//                       o dado antigo enquanto refaz o fetch = vazamento visível)
//   3. resetar as fatias de UI por workspace (filtros etc.)
//   4. gravar o novo wsId
// A navegação para `/` fica com o chamador (é do router). Trocar `clear()` por
// `invalidateQueries()` faz o teste 5.5 vermelho.

type ResetFn = () => void
const resets = new Set<ResetFn>()

/** Fatias de UI por workspace registram aqui seu reset (chamado na troca). */
export function registerWorkspaceReset(fn: ResetFn): () => void {
  resets.add(fn)
  return () => resets.delete(fn)
}

export async function switchWorkspace(id: string): Promise<void> {
  if (useWorkspaceStore.getState().currentWorkspaceId === id) return // já corrente: sem efeito

  await queryClient.cancelQueries()
  queryClient.clear()
  // offline-pwa — o snapshot persistido acompanha o `clear()`: sem isto, o cache
  // de leitura do workspace anterior sobreviveria no disco e um reload o
  // reidrataria (vazamento entre tenants no dispositivo). O novo workspace
  // repovoa e repersiste ao carregar.
  void purgeQueryCache()
  resets.forEach((fn) => fn())
  useWorkspaceStore.getState().selectWorkspace(id)
}
