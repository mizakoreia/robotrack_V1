import { toast } from 'sonner'
import { authApi, invitationsApi } from '../api/endpoints'
import { useAuthStore } from '../../store/authStore'
import { useWorkspaceStore } from '../../store/workspaceStore'
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
  inviteStore.clearCode()
  queryClient.clear()
  redirect('/entrar')
}

// Aceite por CÓDIGO pós-autenticação (code-only-invites — o único caminho). REUSA
// o mapa de erros de convite, com os estados próprios do código:
// `invitation_code_locked` (423 — travado após tentativas) e o genérico de par
// inválido (`invitation_not_found`, que aqui vira "código ou e-mail incorretos" em
// vez de "convite não encontrado"). O par é REMOVIDO do storage ANTES do await,
// para um mismatch não se repetir a cada navegação.
//
// Retorna `true` SOMENTE no aceite bem-sucedido. O valor é ignorado pelos
// chamadores de OAuth (AuthPage, handleInviteAfterAuth), mas o diálogo in-app de
// `join-workspace-by-code` o usa para só fechar/navegar quando entrou de
// fato — em erro (toast já exibido) o diálogo permanece aberto com o código
// digitado. O feedback ao usuário continua sendo o toast (canal único de convite).
export async function consumeInviteByCode(code: string, email: string): Promise<boolean> {
  inviteStore.clearCode()

  if (typeof navigator !== 'undefined' && navigator.onLine === false) {
    toast.warning(inviteText.offline, { duration: Infinity })
    return false
  }

  try {
    const result = await invitationsApi.acceptByCode({ code, email })
    if (result?.workspace_id) {
      useWorkspaceStore.getState().selectWorkspace(result.workspace_id)
    }
    toast.success(inviteText.accepted(null))
    return true
  } catch (e) {
    const resposta = (e as { response?: { status?: number; data?: { error?: string } } })?.response
    const status = resposta?.status
    const codigo = resposta?.data?.error

    if (codigo === 'invitation_code_locked' || status === 423) {
      toast.warning(inviteText.codeLocked, { duration: Infinity })
    } else if (codigo === 'invitation_code_expired') {
      toast.warning(inviteText.codeExpired)
    } else if (status === 410 || codigo === 'invitation_expired') {
      toast.warning(inviteText.expired)
    } else if (codigo === 'invitation_already_used') {
      toast.warning(inviteText.alreadyUsed)
    } else if (codigo === 'already_member') {
      toast.info(inviteText.alreadyMember)
    } else if (codigo === 'invitation_email_mismatch') {
      // O par (código+e-mail) casou, mas a conta autenticada é outra. O e-mail
      // mascarado vem do preview por código (mesmo par), e a ação é trocar de conta.
      const mascarado = await emailMascaradoDoConvitePorCodigo(code, email)
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
    } else if (status === 404 || codigo === 'invitation_not_found') {
      // Par inválido (código ou e-mail errado) — genérico de propósito no servidor.
      toast.error(inviteText.codeInvalidPair)
    } else {
      toast.error(inviteText.genericFailure)
    }
    return false
  }
}

async function emailMascaradoDoConvitePorCodigo(code: string, email: string): Promise<string | null> {
  try {
    const preview = await invitationsApi.previewByCode({ code, email })
    return preview.email_masked
  } catch {
    return null
  }
}

// Convite após autenticar (identity-and-auth 6.5/6.6). Se há o par código+e-mail
// guardado, aceita UMA única vez. Se NÃO há par mas a entrada foi por um convite
// (marcador), o par se perdeu no redirect do Google com storage bloqueado:
// orienta a reabrir — jamais descarta o convite em silêncio.
export async function handleInviteAfterAuth(): Promise<void> {
  const codePair = inviteStore.readCode()

  if (codePair) {
    await consumeInviteByCode(codePair.code, codePair.email)
  } else if (oauthState.wasInviteEntry()) {
    toast.warning(inviteText.lostToken)
  }

  oauthState.clearInviteEntry()
}
