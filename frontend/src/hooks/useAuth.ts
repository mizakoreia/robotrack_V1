import { useState, useCallback, useEffect } from 'react'
import { useAuthStore } from '@/store/authStore'
import { authService } from '@/lib/api/auth'
import { toast } from 'sonner'

export const useAuth = () => {
  const {
    loginMethod,
    identifier,
    loginCode,
    isLoading,
    error,
    setLoginMethod,
    setIdentifier,
    setLoginCode,
    setLoading,
    setError,
    clearError,
    setAuth,
    setDevCode,
    logout: logoutStore,
    isAuthenticated
  } = useAuthStore()

  const [isValidating, setIsValidating] = useState(false)
  const [lastRequestTime, setLastRequestTime] = useState<number>(0)
  const REQUEST_COOLDOWN = 3000 // 3 segundos entre requisições
  const [refreshTimerId, setRefreshTimerId] = useState<number | null>(null)

  // Validação de email
  const validateEmail = (email: string): boolean => {
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/
    return emailRegex.test(email)
  }

  // Validação de WhatsApp (número brasileiro)
  const validateWhatsApp = (phone: string): boolean => {
    const cleanPhone = phone.replace(/\D/g, '')
    return cleanPhone.length >= 11 && cleanPhone.length <= 15
  }

  // Solicitar código de login
  const requestMagicLogin = useCallback(async () => {
    if (!identifier.trim()) {
      setError('Por favor, insira seu email ou número de WhatsApp')
      return
    }

    // Validação baseada no método
    if (loginMethod === 'email' && !validateEmail(identifier)) {
      setError('Por favor, insira um email válido')
      return
    }

    if (loginMethod === 'whatsapp' && !validateWhatsApp(identifier)) {
      setError('Por favor, insira o WhatsApp com código do país sem + (ex: 5511999999999)')
      return
    }

    // Rate limiting - verificar cooldown
    const now = Date.now()
    const timeSinceLastRequest = now - lastRequestTime
    if (timeSinceLastRequest < REQUEST_COOLDOWN) {
      const remainingTime = Math.ceil((REQUEST_COOLDOWN - timeSinceLastRequest) / 1000)
      setError(`Aguarde ${remainingTime} segundos antes de solicitar um novo código`)
      return
    }

    setLoading(true)
    setError(null)
    setLastRequestTime(now)

    try {
      const normalizedIdentifier = loginMethod === 'whatsapp'
        ? identifier.replace(/\D/g, '')
        : identifier.trim()
      const response = await authService.preRegister({
        identifier: normalizedIdentifier,
        method: loginMethod
      })

      console.log('Magic login code requested successfully:', { identifier, method: loginMethod })
      if (import.meta.env.MODE === 'development' && (response as any)?.code) {
        setDevCode((response as any).code)
      } else {
        setDevCode(null)
      }
      return true
    } catch (error: any) {
      const errorMessage = error.response?.data?.error?.message || 'Erro ao enviar código'
      console.error('Magic login request failed:', error)
      setError(errorMessage)
      return false
    } finally {
      setLoading(false)
    }
  }, [identifier, loginMethod, setLoading, setError])

  // Agendar refresh antes da expiração
  useEffect(() => {
    // Sem auto-refresh: manter sessão até expirar e então deslogar
    if (refreshTimerId) window.clearTimeout(refreshTimerId)
    setRefreshTimerId(null)
  }, [isAuthenticated])

  // Validar código de 6 dígitos
  const validateMagicCode = useCallback(async () => {
    const { loginCode: currentCode, identifier: currentIdentifier, loginMethod: currentMethod } = useAuthStore.getState()
    if (!currentCode.trim()) {
      setError('Por favor, insira o código recebido')
      return false
    }

    if (currentCode.length !== 6) {
      setError('O código deve ter 6 dígitos')
      return false
    }

    // Validação de caracteres numéricos apenas
    if (!/^\d{6}$/.test(currentCode)) {
      setError('O código deve conter apenas números')
      return false
    }

    // Rate limiting para validação
    const now = Date.now()
    const timeSinceLastRequest = now - lastRequestTime
    if (timeSinceLastRequest < REQUEST_COOLDOWN) {
      const remainingTime = Math.ceil((REQUEST_COOLDOWN - timeSinceLastRequest) / 1000)
      setError(`Aguarde ${remainingTime} segundos antes de tentar novamente`)
      return false
    }

    if (!currentIdentifier) {
      setError('Identificador não encontrado')
      return false
    }

    setIsValidating(true)
    setError(null)
    setLastRequestTime(now)

    try {
      const result = await authService.verifyPreRegisterCode({
        identifier: currentIdentifier,
        code: currentCode,
        method: currentMethod
      })
      if (result.access_token && result.user) {
        // Persistir tokens
        localStorage.setItem('access_token', result.access_token)
        if (result.refresh_token) localStorage.setItem('refresh_token', result.refresh_token)
        setAuth({ accessToken: result.access_token, refreshToken: result.refresh_token || '' }, result.user as any)
        // Validar sessão no backend antes de redirecionar
        const status = await authService.checkSessionStatus()
        if (status?.authenticated || status?.valid) {
          window.location.href = '/dashboard'
          return 'login'
        }
        // Sessão inválida: limpar e informar
        localStorage.removeItem('access_token')
        localStorage.removeItem('refresh_token')
        useAuthStore.getState().logout()
        toast.error('Sessão inválida. Faça login novamente.')
        return 'invalid'
      }
      if (result.requires_completion) {
        return 'complete'
      }
      return 'invalid'
    } catch (error: any) {
      const errorMessage = error.response?.data?.error?.message || 'Código inválido ou expirado'
      console.error('Magic login validation failed:', error)
      setError(errorMessage)
      return 'invalid'
    } finally {
      setIsValidating(false)
    }
  }, [loginCode, identifier, loginMethod, setAuth, setError])

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
    loginCode,
    isLoading,
    isValidating,
    error,
    
    // Actions
    setLoginMethod,
    setIdentifier,
    setLoginCode,
    clearError,
    requestMagicLogin,
    validateMagicCode,
    loginWithGoogle,
    loginWithFacebook,
    logout,
    checkSession
  }
}
