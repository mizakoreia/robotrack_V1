import { apiClient } from './client'
/* import { toast } from 'sonner' */




export interface AuthResponse {
  access_token: string
  refresh_token: string
  user: {
    id: string
    email?: string
    whatsapp?: string
    name?: string
    avatar?: string
  }
}


export interface OAuthUrlResponse {
  url: string
  provider?: 'google' | 'facebook'
  state?: string
}

export interface OAuthCallbackResponse {
  access_token: string
  refresh_token: string
  user: {
    id: string
    email?: string
    whatsapp?: string
    name?: string
    avatar?: string
  }
}

export interface SessionStatusResponse {
  // Alguns backends retornam `authenticated`; outros retornam `valid`.
  // Mantemos ambos por compatibilidade e normalizamos na função.
  authenticated?: boolean
  valid?: boolean
  user: {
    id: string
    email?: string
    whatsapp?: string
    name?: string
    avatar?: string
  } | null
  expires_at?: string
  csrf_token?: string | null
}

export interface RefreshTokenResponse {
  access_token: string
  refresh_token: string
}

class AuthService {
  // OAuth - Google
  async getGoogleAuthUrl(): Promise<OAuthUrlResponse> {
    try {
      return await apiClient.get<OAuthUrlResponse>('/auth/v1/oauth/google_url')
    } catch (error) {
      throw error
    }
  }

  // OAuth - Facebook
  async getFacebookAuthUrl(): Promise<OAuthUrlResponse> {
    try {
      return await apiClient.get<OAuthUrlResponse>('/auth/v1/oauth/facebook_url')
    } catch (error) {
      throw error
    }
  }

  // OAuth - Callback
  async handleOAuthCallback(provider: 'google' | 'facebook', code: string): Promise<OAuthCallbackResponse> {
    try {
      const response = await apiClient.post<any>(`/auth/v1/oauth/callback`, { provider, code })
      const normalized: OAuthCallbackResponse = {
        access_token: response.access_token ?? response.token,
        refresh_token: response.refresh_token,
        user: response.user
      }
      return normalized
    } catch (error) {
      throw error
    }
  }

  // Sessão - Status
  async checkSessionStatus(): Promise<SessionStatusResponse> {
    try {
      const raw = await apiClient.get<any>('/auth/v1/sessions/status')
      const normalized: SessionStatusResponse = {
        authenticated: raw?.authenticated ?? raw?.valid ?? false,
        valid: raw?.valid,
        user: raw?.user ?? null,
        expires_at: raw?.expires_at,
        csrf_token: raw?.csrf_token ?? null,
      }
      return normalized
    } catch (error) {
      // Não mostrar erro para verificação de sessão
      throw error
    }
  }

  // Sessão - Refresh Token
  async refreshAccessToken(refreshToken: string): Promise<RefreshTokenResponse> {
    try {
      return await apiClient.post<RefreshTokenResponse>('/auth/v1/sessions/refresh', {
        refresh_token: refreshToken
      })
    } catch (error) {
      throw error
    }
  }

  // Sessão - Logout
  async logout(): Promise<void> {
    try {
      await apiClient.delete('/auth/v1/sessions/logout')
    } catch (error) {
      throw error
    }
  }
}

export const authService = new AuthService()
