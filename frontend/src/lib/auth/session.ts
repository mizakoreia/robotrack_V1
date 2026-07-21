import { toast } from 'sonner'
import { authApi } from '../api/endpoints'
import { useAuthStore } from '../../store/authStore'
import { queryClient } from '../queryClient'
import { inviteStore } from './invite'
import { oauthState } from './oauthState'

// Logout (identity-and-auth 6.7). Chama DELETE /auth/v1/session, mas limpa o
// estado LOCAL mesmo se a rede falhar — a sessão local nunca fica presa por causa
// do servidor. `queryClient.clear()` garante que o cache do usuário anterior não
// seja servido ao próximo na mesma aba.
export async function performLogout(redirect: (path: string) => void): Promise<void> {
  try {
    await authApi.logout()
  } catch {
    /* limpa local mesmo assim */
  }
  useAuthStore.getState().clearSession()
  inviteStore.clear()
  queryClient.clear()
  redirect('/entrar')
}

// Convite após autenticar (identity-and-auth 6.5/6.6). Se há token guardado,
// aceita UMA única vez (a chave é removida antes do await, então uma recarga não
// o reconsome) e trata 410 (expirado) mantendo o usuário autenticado, com aviso.
// Se NÃO há token mas a entrada foi por um link de convite (marcador), o token se
// perdeu no redirect do Google com storage bloqueado (6.6): orienta a reabrir o
// link — jamais descarta o convite em silêncio.
export async function handleInviteAfterAuth(): Promise<void> {
  const token = inviteStore.read()

  if (token) {
    inviteStore.clear()
    try {
      await authApi.acceptInvite(token)
    } catch (e) {
      const status = (e as { response?: { status?: number } })?.response?.status
      if (status === 410) {
        toast.warning('Este convite expirou. Peça um novo ao administrador do workspace.')
      } else {
        toast.error('Não foi possível aceitar o convite agora.')
      }
    }
  } else if (oauthState.wasInviteEntry()) {
    toast.warning('Não conseguimos recuperar seu convite neste navegador. Você já está conectado — reabra o link do convite.')
  }

  oauthState.clearInviteEntry()
}
