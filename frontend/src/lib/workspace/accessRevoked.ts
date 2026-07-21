import { toast } from 'sonner'
import { queryClient } from '../queryClient'
import { useWorkspaceStore } from '../../store/workspaceStore'
import { inviteText } from '../i18n/invitations'

// team-access-management §"Revogação de acesso em tempo real" (tarefa 5.3 /
// D-INV-7).
//
// UMA rotina, dois gatilhos: o evento `membership_revoked` do WorkspaceChannel
// (quando `realtime-collaboration` existir) e o `403 workspace_access_revoked`
// que o interceptor do apiClient já vê hoje. O caminho puxado funciona SOZINHO —
// é por isso que esta capacidade não ficou bloqueada cinco ondas esperando o
// Cable.
//
// Quatro efeitos, e nenhum é opcional:
//   1. avisa de forma PERSISTENTE (um toast que some sozinho seria a mesma coisa
//      que não avisar, já que a tela muda no mesmo instante);
//   2. remove o workspace do índice local — que é cache de UI, nunca autoridade
//      (invariante 2): reinseri-lo à mão não devolve acesso nenhum;
//   3. descarta o cache React Query com prefixo ['ws', wsId] — sem isso, dados
//      do workspace perdido continuariam renderizados depois da navegação;
//   4. leva ao workspace PRÓPRIO (criado no bootstrap), nunca a uma tela vazia.

let navigator: ((path: string) => void) | null = null

/** O shell registra o `navigate` do react-router; sem ele, cai para o location. */
export function registerRevocationNavigator(fn: ((path: string) => void) | null) {
  navigator = fn
}

function go(path: string) {
  if (navigator) {
    navigator(path)
    return
  }
  try {
    window.location.assign(path)
  } catch {
    /* ambiente sem window (teste): nada a navegar */
  }
}

let lastHandled: string | null = null

export function handleAccessRevoked(workspaceId: string, options: { workspaceName?: string | null } = {}) {
  if (!workspaceId) return

  const store = useWorkspaceStore.getState()
  const perdido = store.workspaces.find((w) => w.id === workspaceId)
  const nome = options.workspaceName ?? perdido?.name ?? null

  // Uma rajada de requisições ao workspace perdido produziria N toasts idênticos.
  const jaTratado = lastHandled === workspaceId
  lastHandled = workspaceId

  const restantes = store.workspaces.filter((w) => w.id !== workspaceId)
  store.setWorkspaces(restantes)

  queryClient.removeQueries({ queryKey: ['ws', workspaceId] })

  const proprio = restantes.find((w) => w.role === 'owner') ?? restantes[0]
  if (proprio) {
    store.selectWorkspace(proprio.id)
  } else {
    store.clear()
  }

  if (!jaTratado) {
    toast.warning(inviteText.accessRevoked(nome), { duration: Infinity })
  }

  go('/dashboard')
}

/** Só para os testes: zera a memória de deduplicação entre exemplos. */
export function resetAccessRevokedState() {
  lastHandled = null
}
