import { apiClient, API_URL } from './client'
import type { User } from './types'

// Superfície de autenticação (identity-and-auth). O envelope de sucesso é
// `{ data: { access_token, user } }`; erros vêm em `error`/`errors` (mapeados
// pelo interceptor de erro no cliente). O Google é um REDIRECT de página inteira
// para o backend — não um endpoint XHR.
export interface AuthUserDTO {
  id: string
  name: string
  email: string
  avatar_url?: string | null
}

export interface AuthEnvelope {
  data: { access_token: string; user: AuthUserDTO }
}

export interface RegisterInput {
  name: string
  email: string
  password: string
  remember_me: boolean
}

export interface LoginInput {
  email: string
  password: string
  remember_me: boolean
}

export const authApi = {
  register: (data: RegisterInput) =>
    apiClient.postPublic<AuthEnvelope>('/auth/v1/registration', data),

  login: (data: LoginInput) =>
    apiClient.postPublic<AuthEnvelope>('/auth/v1/session', data),

  logout: () =>
    apiClient.delete('/auth/v1/session'),

  renew: () =>
    apiClient.post<AuthEnvelope>('/auth/v1/session/renew'),

  me: () =>
    apiClient.get<{ data: { user: AuthUserDTO } }>('/auth/v1/me'),

  // Edição de perfil é do template (fora do escopo de identity-and-auth, que
  // enxugou GET /auth/v1/me). Mantido para compat de ProfilePage.
  updateMe: (data: Record<string, unknown>) =>
    apiClient.patch<{ data: { user: AuthUserDTO } }>('/auth/v1/me', data),

  // Redirect de página inteira para o Google (D4.4). `remember_me` viaja em
  // omniauth.params e volta ao callback.
  googleRedirectUrl: (remember: boolean) =>
    `${API_URL}/users/auth/google_oauth2?remember_me=${remember ? 'true' : 'false'}`,

  // Aceite do convite — servido por `workspace-invitations`. Aqui o cliente só
  // repassa o token opaco capturado antes do login.
  acceptInvite: (token: string) =>
    apiClient.post(`/api/v1/invitations/${encodeURIComponent(token)}/accept`),
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

// workspace-core §"Índice do usuário" (workspace-tenancy 6.3). O papel vem no
// item apenas como rótulo — nunca é enviado de volta pelo cliente.
export interface WorkspaceItem {
  id: string
  name: string
  role: string
}

export const workspacesApi = {
  list: () => apiClient.get<WorkspaceItem[]>('/api/v1/workspaces'),
  updateName: (id: string, name: string) =>
    apiClient.patch<WorkspaceItem>(`/api/v1/workspaces/${id}`, { name }),
}
