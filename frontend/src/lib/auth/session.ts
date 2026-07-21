import { toast } from 'sonner'
import { authApi, invitationsApi } from '../api/endpoints'
import { useAuthStore } from '../../store/authStore'
import { queryClient } from '../queryClient'
import { inviteStore } from './invite'
import { oauthState } from './oauthState'
import { inviteText } from '../i18n/invitations'

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

// Aceite de convite pós-autenticação (workspace-invitations 5.2 / identity-and-auth
// 6.5-6.6). Chamado com um token já em mãos.
//
// A regra que evita o pior modo de falha: o token é REMOVIDO do storage ANTES do
// await, em qualquer desfecho. Se ficasse, um `403 invitation_email_mismatch`
// (o caso mais provável — a pessoa entrou com a conta errada) se repetiria a
// cada navegação, num laço que ela não teria como quebrar.
//
// Os desfechos são distinguidos pelo CÓDIGO do servidor, não pelo status solto:
// "expirou" e "já usado" são ambos conflito para o usuário, mas dizem coisas
// diferentes sobre o que fazer a seguir.
export async function consumeInvite(token: string): Promise<void> {
  inviteStore.clear()

  if (typeof navigator !== 'undefined' && navigator.onLine === false) {
    toast.warning(inviteText.offline, { duration: Infinity })
    return
  }

  try {
    await invitationsApi.accept(token)
    toast.success(inviteText.accepted(null))
  } catch (e) {
    const resposta = (e as { response?: { status?: number; data?: { error?: string } } })?.response
    const status = resposta?.status
    const codigo = resposta?.data?.error

    if (status === 410 || codigo === 'invitation_expired') {
      toast.warning(inviteText.expired)
    } else if (codigo === 'invitation_already_used') {
      toast.warning(inviteText.alreadyUsed)
    } else if (codigo === 'already_member') {
      toast.info(inviteText.alreadyMember)
    } else if (codigo === 'invitation_email_mismatch') {
      // Único caso com AÇÃO oferecida: a pessoa precisa trocar de conta, e o
      // e-mail mascarado do convite é a única pista que ela tem de qual usar.
      const mascarado = await emailMascaradoDoConvite(token)
      toast.warning(inviteText.emailMismatch(mascarado), {
        duration: Infinity,
        action: {
          label: inviteText.emailMismatchAction,
          onClick: () => {
            void performLogout((path) => {
              try {
                window.location.assign(path)
              } catch {
                /* sem window */
              }
            })
          },
        },
      })
    } else if (codigo === 'person_email_conflict') {
      toast.error(inviteText.personConflict, { duration: Infinity })
    } else if (status === 404) {
      toast.error(inviteText.previewNotFound)
    } else {
      toast.error(inviteText.genericFailure)
    }
  }
}

// A pré-visualização é pública, então dá para recuperar o e-mail mascarado
// mesmo depois do 403 — sem ela a mensagem seria "este convite é para outra
// pessoa", e o usuário ficaria sem saber qual conta usar.
async function emailMascaradoDoConvite(token: string): Promise<string | null> {
  try {
    const preview = await invitationsApi.preview(token)
    return preview.email_masked
  } catch {
    return null
  }
}

// Convite após autenticar (identity-and-auth 6.5/6.6). Se há token guardado,
// aceita UMA única vez. Se NÃO há token mas a entrada foi por um link de convite
// (marcador), o token se perdeu no redirect do Google com storage bloqueado:
// orienta a reabrir o link — jamais descarta o convite em silêncio.
export async function handleInviteAfterAuth(): Promise<void> {
  const token = inviteStore.read()

  if (token) {
    await consumeInvite(token)
  } else if (oauthState.wasInviteEntry()) {
    toast.warning(inviteText.lostToken)
  }

  oauthState.clearInviteEntry()
}
