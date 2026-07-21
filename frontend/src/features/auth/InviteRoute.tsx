import { useEffect, useRef } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { toast } from 'sonner'
import { authApi } from '../../lib/api/endpoints'
import { useAuthStore } from '../../store/authStore'
import { inviteStore } from '../../lib/auth/invite'
import { oauthState } from '../../lib/auth/oauthState'

// Rota `/convite/:token` (identity-and-auth 6.4 / §3.1). SEM sessão: grava o token
// em sessionStorage ANTES de ir para /entrar, para consumi-lo logo após
// autenticar (sobrevive inclusive ao redirect do Google). COM sessão: aceita
// direto, sem passar por /entrar e sem gravar nada.
export function InviteRoute() {
  const { token } = useParams<{ token: string }>()
  const navigate = useNavigate()
  const ran = useRef(false)

  useEffect(() => {
    if (ran.current || !token) return
    ran.current = true

    if (useAuthStore.getState().isAuthenticated) {
      authApi
        .acceptInvite(token)
        .catch((e: { response?: { status?: number } }) => {
          if (e?.response?.status === 410) {
            toast.warning('Este convite expirou. Peça um novo ao administrador do workspace.')
          } else {
            toast.error('Não foi possível aceitar o convite agora.')
          }
        })
        .finally(() => navigate('/dashboard'))
      return
    }

    // Sem sessão: marca a entrada como convite (para detectar perda no redirect)
    // e guarda o token antes de mandar para o login.
    oauthState.markInviteEntry()
    inviteStore.capture(token)
    navigate('/entrar')
  }, [token, navigate])

  return (
    <div className="min-h-screen flex items-center justify-center">
      <div className="text-center text-muted-foreground">Abrindo o convite…</div>
    </div>
  )
}
