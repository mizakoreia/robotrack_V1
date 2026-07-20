import { useState, useCallback, useEffect } from 'react'
import { useAuthStore } from '@/store/authStore'
import { authService } from '@/lib/api/auth'
import { toast } from 'sonner'

export const useAuth = () => {
  const {
    loginMethod,
    identifier,
    isLoading,
    error,
    setLoginMethod,
    setIdentifier,
    clearError,
    logout: logoutStore,
    isAuthenticated
  } = useAuthStore()

  const [refreshTimerId, setRefreshTimerId] = useState<number | null>(null)

  // Agendar refresh antes da expiração
  useEffect(() => {
    // Sem auto-refresh: manter sessão até expirar e então deslogar
    if (refreshTimerId) window.clearTimeout(refreshTimerId)
    setRefreshTimerId(null)
  }, [isAuthenticated])

  // Login com Google
  const loginWithGoogle = useCallback(async () => {
    try {
      const response = await authService.getGoogleAuthUrl()
      if (response.state) localStorage.setItem('oauth_state', response.state)
      localStorage.setItem('oauth_provider', 'google')
      window.location.href = response.url
    } catch (error) {
      toast.error('Erro ao conectar com Google')
    }
  }, [])

  // Login com Facebook
  const loginWithFacebook = useCallback(async () => {
    try {
      const response = await authService.getFacebookAuthUrl()
      if (response.state) localStorage.setItem('oauth_state', response.state)
      localStorage.setItem('oauth_provider', 'facebook')
      window.location.href = response.url
    } catch (error) {
      toast.error('Erro ao conectar com Facebook')
    }
  }, [])

  // Logout
  const logout = useCallback(async () => {
    try {
      await authService.logout()
    } catch (error) {
      console.error('Erro ao fazer logout:', error)
    } finally {
      // Limpar localStorage
      localStorage.removeItem('access_token')
      localStorage.removeItem('refresh_token')
      
      // Limpar store
      logoutStore()
      
      // Redirecionar para login
      window.location.href = '/login'
    }
  }, [logoutStore])

  // Verificar status da sessão
  const checkSession = useCallback(async () => {
    try {
      const response = await authService.checkSessionStatus()
      return response
    } catch (error: any) {
      if (error.response?.status === 401) {
        return { authenticated: false, user: null }
      }
      throw error
    }
  }, [logoutStore])

  return {
    // Estado
    loginMethod,
    identifier,
    isLoading,
    error,

    // Actions
    setLoginMethod,
    setIdentifier,
    clearError,
    loginWithGoogle,
    loginWithFacebook,
    logout,
    checkSession
  }
}
