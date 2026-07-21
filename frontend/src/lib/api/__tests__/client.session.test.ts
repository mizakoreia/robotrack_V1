import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import type { AxiosRequestConfig, AxiosResponse } from 'axios'
import { apiClient } from '../client'
import { useAuthStore } from '../../../store/authStore'

// identity-and-auth 6.3/6.8 / D4.3: NÃO há renovação transparente. Um 401 numa
// chamada autenticada ENCERRA a sessão — limpa o store e não dispara refresh. O
// bug do template era o interceptor entrar em laço de refresh contra um token
// permanentemente inválido. Aqui se prova que há, no máximo, UMA requisição em
// resposta ao 401 (a própria, que falha) e nenhuma de renovação.

// @ts-expect-error — acesso ao axios interno para instrumentar o teste
const axiosInstance = apiClient.client as { defaults: { adapter: unknown } }

type Rota = (config: AxiosRequestConfig) => [number, unknown]

function instalarAdapter(rotas: Record<string, Rota>, registro: AxiosRequestConfig[]) {
  axiosInstance.defaults.adapter = async (config: AxiosRequestConfig) => {
    registro.push(config)
    const chave = `${(config.method || 'get').toUpperCase()} ${config.url}`
    const rota = rotas[chave]
    if (!rota) throw new Error(`rota não mockada: ${chave}`)
    const [status, data] = rota(config)
    const response = { data, status, statusText: String(status), headers: {}, config } as AxiosResponse
    if (status >= 400) {
      const erro = new Error(`Request failed with status code ${status}`) as Error & {
        response: AxiosResponse; config: AxiosRequestConfig; isAxiosError: boolean
      }
      erro.response = response
      erro.config = config
      erro.isAxiosError = true
      throw erro
    }
    return response
  }
}

describe('apiClient — 401 encerra a sessão, sem laço de refresh', () => {
  const adapterOriginal = axiosInstance.defaults.adapter
  let registro: AxiosRequestConfig[]

  beforeEach(() => {
    registro = []
    useAuthStore.getState().setSession('token-velho', { id: 'u1' }, { remember: false })
  })

  afterEach(() => {
    axiosInstance.defaults.adapter = adapterOriginal
    useAuthStore.getState().clearSession()
  })

  it('a chamada autenticada leva o token do store no Authorization', async () => {
    instalarAdapter({ 'GET /api/v1/a': () => [200, { ok: true }] }, registro)

    await apiClient.get('/api/v1/a')

    expect((registro[0].headers as Record<string, unknown>).Authorization).toBe('Bearer token-velho')
  })

  it('401 numa chamada autenticada encerra a sessão e NÃO tenta refresh nem retenta', async () => {
    instalarAdapter({ 'GET /api/v1/a': () => [401, {}] }, registro)

    await expect(apiClient.get('/api/v1/a')).rejects.toBeTruthy()

    // Sessão encerrada no store.
    expect(useAuthStore.getState().isAuthenticated).toBe(false)
    expect(useAuthStore.getState().accessToken).toBeNull()
    // Uma única chamada ao recurso; nenhuma de renovação (sem laço).
    expect(registro.filter((c) => c.url === '/api/v1/a')).toHaveLength(1)
    expect(registro.some((c) => /refresh|renew|session/.test(c.url || ''))).toBe(false)
  })

  it('getPublic não anexa Authorization nem envia header de bypass', async () => {
    instalarAdapter({ 'GET /api/v1/countries': () => [200, { countries: [] }] }, registro)

    await apiClient.getPublic('/api/v1/countries')

    const headers = registro[0].headers as Record<string, unknown>
    expect(headers.Authorization).toBeUndefined()
    expect(headers['X-Skip-Auth']).toBeUndefined()
  })
})
