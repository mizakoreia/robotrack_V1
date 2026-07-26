import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import { MemoryRouter, Routes, Route } from 'react-router-dom'
import { AxiosError } from 'axios'
import { ProtectedRoute } from '../ProtectedRoute'
import { authApi } from '@/lib/api/endpoints'
import { useAuthStore } from '@/store/authStore'

// fix offline-pwa — a guarda de rota tem de ser TOLERANTE À REDE AUSENTE. O bug
// do dono ("preso tentando registrar" em modo avião) era o app nem BOOTAR offline
// (SW sem precache); com o shell no cache, o app boota e cai aqui. Estes casos
// travam o contrato: sessão local válida + `GET /me` falhando por REDE → ENTRA
// (não trava em "Verificando sessão…", não manda para /entrar). Só um 401
// EXPLÍCITO desloga — e isso é do interceptor do cliente, não desta guarda.
// Login/registro offline seguem impossíveis por natureza (exigem o servidor).

function renderGuard() {
  return render(
    <MemoryRouter initialEntries={['/']}>
      <Routes>
        <Route
          path="/"
          element={
            <ProtectedRoute>
              <div>CONTEUDO_PROTEGIDO</div>
            </ProtectedRoute>
          }
        />
        <Route path="/entrar" element={<div>TELA_ENTRAR</div>} />
      </Routes>
    </MemoryRouter>,
  )
}

beforeEach(() => {
  useAuthStore.setState({ isAuthenticated: false, accessToken: null, user: null })
})
afterEach(() => {
  vi.restoreAllMocks()
})

describe('ProtectedRoute — offline / rede ausente', () => {
  it('sessão local válida + me() falha por REDE (offline) → ENTRA, não trava nem desloga', async () => {
    useAuthStore.setState({ isAuthenticated: true, accessToken: 'tok', user: null })
    // Erro de rede do axios: SEM `response` (status indefinido) — é o que o
    // interceptor NÃO trata como 401, e o que o modo avião produz.
    const netError = new AxiosError('Network Error', 'ERR_NETWORK')
    const meSpy = vi.spyOn(authApi, 'me').mockRejectedValue(netError)

    renderGuard()

    // Não fica preso no "Verificando sessão…": resolve para o conteúdo.
    await waitFor(() => expect(screen.getByText('CONTEUDO_PROTEGIDO')).toBeInTheDocument())
    expect(screen.queryByText('TELA_ENTRAR')).not.toBeInTheDocument()
    // A falha de rede NÃO pode ter deslogado a sessão local.
    expect(useAuthStore.getState().accessToken).toBe('tok')
    expect(meSpy).toHaveBeenCalled()
  })

  it('sem token (deslogado) + offline → estado claro: vai para /entrar, sem spinner infinito', async () => {
    useAuthStore.setState({ isAuthenticated: false, accessToken: null, user: null })
    const meSpy = vi.spyOn(authApi, 'me').mockRejectedValue(new AxiosError('Network Error', 'ERR_NETWORK'))

    renderGuard()

    await waitFor(() => expect(screen.getByText('TELA_ENTRAR')).toBeInTheDocument())
    expect(screen.queryByText('Verificando sessão…')).not.toBeInTheDocument()
    // Sem sessão não há o que revalidar — não chama a rede.
    expect(meSpy).not.toHaveBeenCalled()
  })
})
