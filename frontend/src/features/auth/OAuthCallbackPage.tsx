import { useEffect, useRef } from 'react'
import { useNavigate } from 'react-router-dom'
import { toast } from 'sonner'
import { authApi } from '../../lib/api/endpoints'
import { useAuthStore } from '../../store/authStore'
import { withStorageTimeout } from '../../lib/safeStorage'
import { oauthState } from '../../lib/auth/oauthState'
import { handleInviteAfterAuth } from '../../lib/auth/session'

// Callback do Google no cliente (identity-and-auth 5.4/6.6 / D4.4). Lê o token do
// FRAGMENTO, apaga o fragmento da barra de endereço com history.replaceState
// ANTES de qualquer navegação (para copiar a URL ou voltar no histórico não
// expor o token), grava a sessão conforme o "manter conectado" escolhido antes do
// redirect, e consome o convite (ou orienta a reabri-lo, se perdido).
export function OAuthCallbackPage() {
  const navigate = useNavigate()
  const ran = useRef(false)

  useEffect(() => {
    if (ran.current) return // StrictMode/reexecução: consome o fragmento uma vez.
    ran.current = true

    const hash = window.location.hash.replace(/^#/, '')
    const params = new URLSearchParams(hash)
    const accessToken = params.get('access_token')
    const errorCode = params.get('error')

    // Apaga o fragmento da barra e do histórico, sempre.
    try {
      window.history.replaceState(null, '', window.location.pathname + window.location.search)
    } catch {
      /* ignore */
    }

    async function run() {
      if (errorCode) {
        toast.error(
          errorCode === 'email_nao_verificado'
            ? 'Seu e-mail do Google não está verificado.'
            : 'O acesso pelo Google foi negado.',
        )
        oauthState.clearRemember()
        navigate('/entrar')
        return
      }

      if (!accessToken) {
        // Aberto direto, sem fragmento: volta ao login sem exceção.
        navigate('/entrar')
        return
      }

      const remember = oauthState.getRemember()
      oauthState.clearRemember()

      const { timedOut } = await withStorageTimeout(() => {
        useAuthStore.getState().setSession(accessToken, null, { remember })
        return useAuthStore.getState().memoryOnly
      })
      if (timedOut || useAuthStore.getState().memoryOnly) {
        toast.warning('Sua sessão não vai persistir neste navegador.')
      }

      // O fragmento traz só o token; o usuário vem de GET /auth/v1/me.
      try {
        const { data } = await authApi.me()
        useAuthStore.getState().setUser(data.user)
      } catch {
        /* segue autenticado; o /me pode ser recarregado depois */
      }

      await handleInviteAfterAuth()
      navigate('/dashboard')
    }

    void run()
  }, [navigate])

  return (
    <div className="min-h-screen flex items-center justify-center">
      <div className="text-center text-muted-foreground">Concluindo o acesso…</div>
    </div>
  )
}
