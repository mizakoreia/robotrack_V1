import { apiClient } from './client'
import type { 
  LoginRequest, 
  LoginResponse, 
  RefreshTokenResponse,
  User,
} from './types'

export const authApi = {
  // Magic Login - Request code
  requestMagicCode: (identifier: string, method: 'email' | 'whatsapp') => 
    apiClient.post<{ success: boolean; message: string }>('/auth/v1/magic_login/request_code', { identifier, method }),
  
  // Magic Login - Validate code and login
  validateMagicCode: (identifier: string, code: string, method: 'email' | 'whatsapp') =>
    apiClient.post<LoginResponse>('/auth/v1/magic_login/validate_code', { identifier, code, method }),
  
  // Check if can resend code
  canResendCode: (identifier: string, method: 'email' | 'whatsapp') =>
    apiClient.post<{ can_resend: boolean; remaining_time?: number }>('/auth/v1/magic_login/can_resend', { identifier, method }),
  
  // OAuth URLs
  getGoogleAuthUrl: (redirectUri?: string) =>
    apiClient.get<{ url: string }>(`/auth/v1/oauth/google_url${redirectUri ? `?redirect_uri=${redirectUri}` : ''}`),
  
  getFacebookAuthUrl: (redirectUri?: string) =>
    apiClient.get<{ url: string }>(`/auth/v1/oauth/facebook_url${redirectUri ? `?redirect_uri=${redirectUri}` : ''}`),
  
  // OAuth callback
  handleOAuthCallback: (provider: 'google' | 'facebook', code: string, state?: string) =>
    apiClient.post<LoginResponse>('/auth/v1/oauth/callback', { provider, code, state }),
  
  // Session management
  refresh: (refreshToken: string) =>
    apiClient.post<RefreshTokenResponse>('/auth/v1/sessions/refresh', { refresh_token: refreshToken }),
  
  logout: () =>
    apiClient.post('/auth/v1/sessions/logout'),
  
  getSessionStatus: () =>
    apiClient.get<{ valid: boolean; user?: User }>('/auth/v1/sessions/status'),

  // Legacy endpoints (deprecated)
  login: (data: LoginRequest) => 
    apiClient.post<LoginResponse>('/auth/v1/login', data),
  
  me: () =>
    apiClient.get<User>('/auth/v1/me'),
  updateMe: (data: Partial<User>) =>
    apiClient.patch<User>('/auth/v1/me', data, { headers: { 'X-CSRF-Token': localStorage.getItem('csrf_token') || 'dev' } }),
}

export const usersApi = {
  list: (params?: { page?: number; perPage?: number; q?: string; type?: 'og' | 'client' }) => {
    const page = params?.page ?? 1
    const perPage = params?.perPage ?? 20
    const q = params?.q ? `&q=${encodeURIComponent(params.q)}` : ''
    const type = params?.type ? `&type=${params.type}` : ''
    return apiClient.get<{ users: User[]; total: number }>(`/api/v1/users?page=${page}&per_page=${perPage}${q}${type}`)
  },
  
  get: (id: string) =>
    apiClient.get<User>(`/api/v1/users/${id}`),
  
  create: (data: Partial<User> & { user_type?: string }) =>
    apiClient.post<User>('/api/v1/users', data),
  
  update: (id: string, data: Partial<User> & { user_type?: string }) =>
    apiClient.patch<User>(`/api/v1/users/${id}`, data),
  
  delete: (id: string) =>
    apiClient.delete(`/api/v1/users/${id}`),

  stats: () =>
    apiClient.get<{ total: number; active: number; recent: number; og_count: number; client_count: number }>(`/api/v1/users/stats`),
}

export const countriesApi = {
  list: (q?: string) => apiClient.get<{ countries: { name: string; iso2: string; dial_code: string }[] }>(`/api/v1/countries${q ? `?q=${encodeURIComponent(q)}` : ''}`)
}
