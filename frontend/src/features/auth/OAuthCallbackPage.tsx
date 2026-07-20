import { useEffect } from 'react'
import { useSearchParams } from 'react-router-dom'
import { authService } from '@/lib/api/auth'
import { toast } from 'sonner'
import { useAuthStore } from '@/store/authStore'

export function OAuthCallbackPage() {
  const [params] = useSearchParams()
  const code = params.get('code') || ''
  const state = params.get('state') || ''
  const providerParam = (params.get('provider') || '').toLowerCase()
  const providerStored = localStorage.getItem('oauth_provider') || ''
  const provider = (providerParam || providerStored) as 'google' | 'facebook'
  const tokenFromQuery = params.get('token') || ''
  const refreshFromQuery = params.get('refresh_token') || ''
  const setAuth = useAuthStore((s) => s.setAuth)

  useEffect(() => {
    const run = async () => {
      // Se Devise devolveu tokens diretamente na query
      if (tokenFromQuery && refreshFromQuery) {
        localStorage.setItem('access_token', tokenFromQuery)
        localStorage.setItem('refresh_token', refreshFromQuery)
        setAuth({ accessToken: tokenFromQuery, refreshToken: refreshFromQuery }, {
          id: 'me'
        } as any)
        window.location.href = '/dashboard'
        return
      }

      // Fluxo via code/state (Grape)
      if (!code || !provider) {
        toast.error('Callback inválido')
        window.location.href = '/login'
        return
      }
      try {
        const expectedState = localStorage.getItem('oauth_state')
        if (expectedState && state && expectedState !== state) {
          toast.error('State inválido')
          window.location.href = '/login'
          return
        }
        const resp = await authService.handleOAuthCallback(provider, code)
        localStorage.setItem('access_token', resp.access_token)
        localStorage.setItem('refresh_token', resp.refresh_token)
        setAuth({ accessToken: resp.access_token, refreshToken: resp.refresh_token }, resp.user)
        window.location.href = '/dashboard'
      } catch (e) {
        toast.error('Falha na autenticação OAuth')
        window.location.href = '/login'
      }
    }
    run()
  }, [code, provider, state, tokenFromQuery, refreshFromQuery, setAuth])

  return (
    <div className="min-h-screen flex items-center justify-center">
      <div className="text-center text-muted-foreground">Processando login...</div>
    </div>
  )
}