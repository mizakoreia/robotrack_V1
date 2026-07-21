import { useEffect, useRef, useState, type ReactNode } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { toast } from 'sonner'
import { invitationsApi, type InvitationPreviewDTO } from '../../lib/api/endpoints'
import { useAuthStore } from '../../store/authStore'
import { inviteStore } from '../../lib/auth/invite'
import { oauthState } from '../../lib/auth/oauthState'
import { consumeInvite } from '../../lib/auth/session'
import { inviteText } from '../../lib/i18n/invitations'
import { Button } from '../../components/ui/Button'

// Rota pública `/convite/:token` (workspace-invitations 5.1 / D-INV-6).
//
// Três coisas acontecem aqui, nesta ordem, e a ordem importa:
//
// 1. O token é gravado em `sessionStorage` (mecanismo de identity-and-auth, que
//    sobrevive ao redirect de página inteira do Google).
// 2. `history.replaceState` TROCA a URL por uma sem o token. O token é
//    credencial: deixá-lo na barra de endereço o entrega ao histórico do
//    navegador, ao referrer e a qualquer captura de tela.
// 3. Só então a pré-visualização é buscada — pela rota pública, que devolve o
//    e-mail MASCARADO e o nome do workspace. Sem ela, o convidado faria login
//    sem saber para onde está entrando.
//
// Com sessão ativa, o aceite é imediato e não passa por `/entrar`.
export function InviteRoute() {
  const { token } = useParams<{ token: string }>()
  const navigate = useNavigate()
  const ran = useRef(false)
  const [preview, setPreview] = useState<InvitationPreviewDTO | null>(null)
  const [naoEncontrado, setNaoEncontrado] = useState(false)

  useEffect(() => {
    if (ran.current || !token) return
    ran.current = true

    const autenticado = useAuthStore.getState().isAuthenticated

    // Guarda + limpa a URL SEMPRE, inclusive no caminho autenticado: se o aceite
    // falhar e o usuário recarregar, o token não pode ter ficado na barra.
    oauthState.markInviteEntry()
    inviteStore.capture(token)
    replaceUrl()

    if (autenticado) {
      void consumeInvite(token).finally(() => navigate('/dashboard'))
      return
    }

    invitationsApi
      .preview(token)
      .then((dados) => setPreview(dados))
      .catch((e: { response?: { status?: number } }) => {
        if (e?.response?.status === 404) {
          setNaoEncontrado(true)
          toast.error(inviteText.previewNotFound)
        } else {
          // Pré-visualização é conveniência: se ela falhar por rede, o convite
          // continua guardado e o login segue normalmente.
          navigate('/entrar')
        }
      })
  }, [token, navigate])

  if (naoEncontrado) {
    return (
      <Tela>
        <p className="text-muted-foreground">{inviteText.previewNotFound}</p>
        <Button className="mt-4" onClick={() => navigate('/entrar')}>
          {inviteText.previewContinue}
        </Button>
      </Tela>
    )
  }

  if (!preview) {
    return (
      <Tela>
        <p className="text-muted-foreground">{inviteText.previewLoading}</p>
      </Tela>
    )
  }

  const expirado = preview.status === 'expired'
  const usado = preview.status === 'used'

  return (
    <Tela>
      <h1 className="text-2xl font-semibold">{inviteText.previewTitle}</h1>
      <p className="mt-2 text-lg">{preview.workspace_name}</p>
      <p className="text-muted-foreground">{inviteText.previewRole(preview.role)}</p>
      <p className="mt-4 text-sm text-muted-foreground">{inviteText.previewFor(preview.email_masked)}</p>

      {expirado && <p className="mt-4 text-sm text-destructive">{inviteText.previewExpired}</p>}
      {usado && <p className="mt-4 text-sm text-destructive">{inviteText.previewUsed}</p>}

      {!expirado && !usado && (
        <Button className="mt-6" onClick={() => navigate('/entrar')}>
          {inviteText.previewContinue}
        </Button>
      )}
    </Tela>
  )
}

function replaceUrl() {
  try {
    window.history.replaceState(null, '', '/convite')
  } catch {
    /* ambiente sem history: nada a limpar */
  }
}

function Tela({ children }: { children: ReactNode }) {
  return (
    <div className="min-h-screen flex items-center justify-center">
      <div className="text-center max-w-md px-6">{children}</div>
    </div>
  )
}
