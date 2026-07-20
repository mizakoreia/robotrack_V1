import axios, { AxiosInstance, AxiosRequestConfig, AxiosError } from 'axios'
/* import { toast } from 'sonner' */

const API_URL = import.meta.env.VITE_API_URL || (() => {
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

class ApiClient {
  private client: AxiosInstance
  private isRefreshing = false
  private refreshQueue: Array<(token: string | null) => void> = []

  constructor() {
    this.client = axios.create({
      baseURL: `${API_URL}`,
      timeout: 30000,
      headers: {
        'Content-Type': 'application/json',
      },
    })

    this.setupInterceptors()
  }

  private setupInterceptors() {
    // Request interceptor
    this.client.interceptors.request.use(
      (config) => {
        // Marcador interno: nunca trafega na requisição. O backend não tem —
        // nem pode ter — um header que desligue autenticação.
        const skip = (config as PublicRequestConfig).skipAuth === true
        if (!skip) {
          const token = localStorage.getItem('access_token') || localStorage.getItem('token')
          if (token) {
            config.headers.Authorization = `Bearer ${token}`
          }
        }
        return config
      },
      (error) => {
        return Promise.reject(error)
      }
    )

    this.client.interceptors.response.use(
      (response) => response,
      async (error: AxiosError) => {
        const original = error.config as AxiosRequestConfig & { _retry?: boolean }
        const status = error.response?.status || 0
        const isUnauthorized = status === 401
        if (!isUnauthorized || original._retry) {
          return Promise.reject(error)
        }

        const refreshToken = localStorage.getItem('refresh_token')
        if (!refreshToken) {
          // Sem refresh: sessão inválida, limpar e redirecionar
          localStorage.removeItem('access_token')
          localStorage.removeItem('refresh_token')
          try { (window as any).location.href = '/login' } catch {}
          return Promise.reject(error)
        }

        if (this.isRefreshing) {
          return new Promise((resolve, reject) => {
            this.refreshQueue.push((token) => {
              if (!token) {
                reject(error)
                return
              }
              original._retry = true
              original.headers = { ...(original.headers || {}), Authorization: `Bearer ${token}` }
              this.client.request(original).then(resolve).catch(reject)
            })
          })
        }

        this.isRefreshing = true
        try {
          const { data } = await this.client.post<{ access_token: string; refresh_token: string }>(
            '/auth/v1/sessions/refresh',
            { refresh_token: refreshToken }
          )
          const newAccess = data.access_token
          const newRefresh = data.refresh_token
          if (newAccess) localStorage.setItem('access_token', newAccess)
          if (newRefresh) localStorage.setItem('refresh_token', newRefresh)
          this.refreshQueue.forEach((cb) => cb(newAccess || null))
          this.refreshQueue = []
          original._retry = true
          original.headers = { ...(original.headers || {}), Authorization: `Bearer ${newAccess}` }
          return this.client.request(original)
        } catch (e) {
          this.refreshQueue.forEach((cb) => cb(null))
          this.refreshQueue = []
          // Refresh falhou: sessão inválida, limpar e redirecionar
          localStorage.removeItem('access_token')
          localStorage.removeItem('refresh_token')
          try { (window as any).location.href = '/login' } catch {}
          return Promise.reject(error)
        } finally {
          this.isRefreshing = false
        }
      }
    )
  }

  async get<T>(url: string, config?: AxiosRequestConfig) {
    const response = await this.client.get<T>(url, config)
    return response.data
  }

  async getPublic<T>(url: string, config?: AxiosRequestConfig) {
    const response = await this.client.get<T>(url, { ...(config || {}), skipAuth: true } as PublicRequestConfig)
    return response.data
  }

  async post<T>(url: string, data?: any, config?: AxiosRequestConfig) {
    const response = await this.client.post<T>(url, data, config)
    return response.data
  }

  async postPublic<T>(url: string, data?: any, config?: AxiosRequestConfig) {
    const response = await this.client.post<T>(url, data, { ...(config || {}), skipAuth: true } as PublicRequestConfig)
    return response.data
  }

  async put<T>(url: string, data?: any, config?: AxiosRequestConfig) {
    const response = await this.client.put<T>(url, data, config)
    return response.data
  }

  async patch<T>(url: string, data?: any, config?: AxiosRequestConfig) {
    const response = await this.client.patch<T>(url, data, config)
    return response.data
  }

  async delete<T>(url: string, config?: AxiosRequestConfig) {
    const response = await this.client.delete<T>(url, config)
    return response.data
  }
}

export const apiClient = new ApiClient()
