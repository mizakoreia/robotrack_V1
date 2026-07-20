import { create } from 'zustand'
import { persist } from 'zustand/middleware'

export type LoginMethod = 'email' | 'whatsapp'

interface AuthState {
  // Estado do login
  isAuthenticated: boolean
  accessToken: string | null
  refreshToken: string | null
  user: User | null
  
  // Estado do magic login
  loginMethod: LoginMethod
  identifier: string // email ou whatsapp
  loginCode: string // código de 6 dígitos
  isLoading: boolean
  error: string | null
  devCode: string | null
  
  // Actions
  setLoginMethod: (method: LoginMethod) => void
  setIdentifier: (identifier: string) => void
  setLoginCode: (code: string) => void
  setLoading: (loading: boolean) => void
  setError: (error: string | null) => void
  setAuth: (tokens: { accessToken: string; refreshToken: string }, user: User) => void
  logout: () => void
  clearError: () => void
  setDevCode: (code: string | null) => void
  renewTokens?: (accessToken: string, refreshToken?: string) => void
  setUser?: (user: User) => void
}

interface User {
  id: string
  email?: string
  phone?: string
  whatsapp?: string
  name?: string
  avatar?: string
  avatar_url?: string
  user_type?: string
  is_og?: boolean
  cpf_cnpj?: string
}

export const useAuthStore = create<AuthState>()(
  persist(
    (set) => ({
      // Estado inicial
      isAuthenticated: false,
      accessToken: null,
      refreshToken: null,
      user: null,
      
      // Magic login state
      loginMethod: 'email',
      identifier: '',
      loginCode: '',
      isLoading: false,
      error: null,
      devCode: null,
      
      // Actions
      setLoginMethod: (method) => set({ loginMethod: method, identifier: '', error: null }),
      setIdentifier: (identifier) => set({ identifier }),
      setLoginCode: (code) => set({ loginCode: code }),
      setLoading: (loading) => set({ isLoading: loading }),
      setError: (error) => set({ error }),
      clearError: () => set({ error: null }),
      setDevCode: (code) => set({ devCode: code }),
      
      setAuth: (tokens, user) => set({
        isAuthenticated: true,
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
        user,
        isLoading: false,
        error: null,
        loginCode: '',
        devCode: null
      }),
      
      logout: () => set({
        isAuthenticated: false,
        accessToken: null,
        refreshToken: null,
        user: null,
        identifier: '',
        loginCode: '',
        isLoading: false,
        error: null,
        devCode: null
      })
      ,
      renewTokens: (accessToken, refreshToken) => set((state) => ({
        isAuthenticated: true,
        accessToken,
        refreshToken: refreshToken ?? state.refreshToken,
      })),
      setUser: (user) => set({ user })
    }),
    {
      name: 'auth-storage',
      partialize: (state) => ({ 
        isAuthenticated: state.isAuthenticated,
        accessToken: state.accessToken,
        refreshToken: state.refreshToken,
        user: state.user
      })
    }
  )
)
