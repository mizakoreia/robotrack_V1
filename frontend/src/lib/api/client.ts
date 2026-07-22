import axios, { AxiosInstance, AxiosRequestConfig, AxiosError } from 'axios'
import { useWorkspaceStore } from '../../store/workspaceStore'
import { useAuthStore } from '../../store/authStore'
import { queryClient } from '../queryClient'

export const API_URL = import.meta.env.VITE_API_URL || (() => {
  try {
    const u = new URL(window.location.origin)
    u.port = '3000'
    return u.origin
  } catch {
    return 'http://localhost:3000'
  }
})()

/** Config interna: `skipAuth` marca chamadas que não devem levar `Authorization`. */
type PublicRequestConfig = AxiosRequestConfig & { skipAuth?: boolean }

// Encerra a sessão local no 401 (identity-and-auth 6.3 / D4.3). NÃO há renovação
// transparente: um 401 significa "sessão acabou" — limpa store + cache e volta
// para /entrar. Isso mata a classe de bug em que o interceptor entra em laço de
// refresh contra um token permanentemente inválido (o comportamento do template).
function endSession() {
  useAuthStore.getState().clearSession()
  queryClient.clear()
  try {
    if (window.location.pathname !== '/entrar') {
      window.location.href = '/entrar'
    }
  } catch {
    /* ambiente sem window (teste): nada a redirecionar */
  }
}

/** Código de erro da API: o envelope de erro é sempre `{ error: '<código>' }`. */
function errorCode(error: AxiosError): string | undefined {
  const data = error.response?.data as { error?: string } | undefined
  return typeof data?.error === 'string' ? data.error : undefined
}

class ApiClient {
  private client: AxiosInstance

  constructor() {
    this.client = axios.create({
      baseURL: `${API_URL}`,
      timeout: 30000,
      headers: { 'Content-Type': 'application/json' },
    })
    this.setupInterceptors()
  }

  private setupInterceptors() {
    this.client.interceptors.request.use(
      (config) => {
        const skip = (config as PublicRequestConfig).skipAuth === true
        if (!skip) {
          // Fonte ÚNICA do token: o authStore (D4.9 / app-shell-navigation 2.1).
          // Nunca lido do armazenamento do navegador aqui — o store é o dono.
          const token = useAuthStore.getState().accessToken
          if (token) {
            config.headers.Authorization = `Bearer ${token}`
          }
          // Contexto de tenant: só o id do workspace corrente trafega. O servidor
          // resolve o papel; o cliente nunca o envia (D9 / workspace-tenancy 6.3).
          const workspaceId = useWorkspaceStore.getState().currentWorkspaceId
          if (workspaceId) {
            config.headers['X-Workspace-Id'] = workspaceId
          }
        }
        return config
      },
      (error) => Promise.reject(error),
    )

    this.client.interceptors.response.use(
      (response) => response,
      (error: AxiosError) => {
        const config = (error.config || {}) as PublicRequestConfig
        const status = error.response?.status || 0
        // 401 numa chamada AUTENTICADA (não pública) encerra a sessão. Chamadas
        // públicas (login/cadastro) tratam o 401 no próprio formulário — não é
        // "sessão expirada", é credencial inválida.
        if (status === 401 && config.skipAuth !== true) {
          endSession()
        }
        // 403 `workspace_access_revoked`: o dono removeu este usuário do
        // workspace enquanto ele estava lá dentro (workspace-invitations 5.3 /
        // D-INV-7). É o caminho PUXADO da detecção — funciona sem ActionCable
        // nenhum, porque o gatilho é a própria negação. `workspace_access_denied`
        // NÃO entra aqui: aquele é o 403 de quem nunca teve acesso, e tratá-lo
        // como revogação apagaria o índice local de quem só digitou o id errado.
        if (status === 403 && config.skipAuth !== true && errorCode(error) === 'workspace_access_revoked') {
          const workspaceId =
            (error.config?.headers?.['X-Workspace-Id'] as string | undefined) ||
            useWorkspaceStore.getState().currentWorkspaceId
          if (workspaceId) {
            void import('../workspace/accessRevoked').then((m) => m.handleAccessRevoked(workspaceId))
          }
        }
        return Promise.reject(error)
      },
    )
  }

  async get<T>(url: string, config?: AxiosRequestConfig) {
    return (await this.client.get<T>(url, config)).data
  }

  async getPublic<T>(url: string, config?: AxiosRequestConfig) {
    return (await this.client.get<T>(url, { ...(config || {}), skipAuth: true } as PublicRequestConfig)).data
  }

  async post<T>(url: string, data?: any, config?: AxiosRequestConfig) {
    return (await this.client.post<T>(url, data, config)).data
  }

  async postPublic<T>(url: string, data?: any, config?: AxiosRequestConfig) {
    return (await this.client.post<T>(url, data, { ...(config || {}), skipAuth: true } as PublicRequestConfig)).data
  }

  async put<T>(url: string, data?: any, config?: AxiosRequestConfig) {
    return (await this.client.put<T>(url, data, config)).data
  }

  async patch<T>(url: string, data?: any, config?: AxiosRequestConfig) {
    return (await this.client.patch<T>(url, data, config)).data
  }

  async delete<T>(url: string, config?: AxiosRequestConfig) {
    return (await this.client.delete<T>(url, config)).data
  }

  // POST que devolve a RESPOSTA crua (corpo como texto + headers) — para downloads
  // (o backup vem com Content-Disposition e o id no header X-Backup-Id).
  async postRaw(url: string, data?: unknown, config?: AxiosRequestConfig) {
    const resp = await this.client.post(url, data, { ...(config || {}), responseType: 'text' })
    return { body: resp.data as string, headers: resp.headers as Record<string, string>, status: resp.status }
  }
}

export const apiClient = new ApiClient()
