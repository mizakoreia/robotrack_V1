import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import type { AxiosRequestConfig, AxiosResponse } from 'axios'
import { apiClient } from '../client'

// O interceptor de 401 com refresh single-flight é o pedaço mais frágil e menos
// testado do frontend, e `offline-pwa` vai depender dele: se duas requisições
// tomarem 401 ao mesmo tempo, tem de ocorrer UM refresh e duas retentativas —
// não dois refreshes, que queimariam um refresh token de uso único.
//
// O adapter do axios é substituído em vez de se usar uma lib de mock: o que se
// quer observar é exatamente a sequência de requisições que sai do cliente.

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
    const response = {
      data,
      status,
      statusText: String(status),
      headers: {},
      config,
    } as AxiosResponse

    if (status >= 400) {
      const erro = new Error(`Request failed with status code ${status}`) as Error & {
        response: AxiosResponse
        config: AxiosRequestConfig
        isAxiosError: boolean
      }
      erro.response = response
      erro.config = config
      erro.isAxiosError = true
      throw erro
    }

    return response
  }
}

describe('apiClient — refresh single-flight no 401', () => {
  const adapterOriginal = axiosInstance.defaults.adapter
  let registro: AxiosRequestConfig[]

  beforeEach(() => {
    registro = []
    localStorage.setItem('access_token', 'token-velho')
    localStorage.setItem('refresh_token', 'refresh-valido')
  })

  afterEach(() => {
    axiosInstance.defaults.adapter = adapterOriginal
    localStorage.clear()
  })

  it('faz exatamente 1 POST de refresh para duas 401 concorrentes, e retenta as duas', async () => {
    const vistos = new Set<string>()

    instalarAdapter(
      {
        'POST /auth/v1/sessions/refresh': () => [
          200,
          { access_token: 'token-novo', refresh_token: 'refresh-novo' },
        ],
        // 401 na primeira passagem de cada recurso, 200 na retentativa.
        'GET /api/v1/a': () => (vistos.has('a') ? [200, { recurso: 'a' }] : (vistos.add('a'), [401, {}])),
        'GET /api/v1/b': () => (vistos.has('b') ? [200, { recurso: 'b' }] : (vistos.add('b'), [401, {}])),
      },
      registro,
    )

    const [a, b] = await Promise.all([
      apiClient.get<{ recurso: string }>('/api/v1/a'),
      apiClient.get<{ recurso: string }>('/api/v1/b'),
    ])

    const refreshes = registro.filter((c) => c.url === '/auth/v1/sessions/refresh')
    const retentativas = registro.filter((c) => c.url === '/api/v1/a' || c.url === '/api/v1/b')

    expect(refreshes).toHaveLength(1)
    expect(retentativas).toHaveLength(4) // 2 iniciais (401) + 2 retentativas
    expect(a).toEqual({ recurso: 'a' })
    expect(b).toEqual({ recurso: 'b' })
    expect(localStorage.getItem('access_token')).toBe('token-novo')
  })

  it('a retentativa leva o token novo no Authorization', async () => {
    let primeira = true

    instalarAdapter(
      {
        'POST /auth/v1/sessions/refresh': () => [
          200,
          { access_token: 'token-novo', refresh_token: 'refresh-novo' },
        ],
        'GET /api/v1/recurso': () => (primeira ? ((primeira = false), [401, {}]) : [200, { ok: true }]),
      },
      registro,
    )

    await apiClient.get('/api/v1/recurso')

    const chamadas = registro.filter((c) => c.url === '/api/v1/recurso')
    expect(chamadas).toHaveLength(2)
    expect((chamadas[1].headers as Record<string, unknown>).Authorization).toBe('Bearer token-novo')
  })

  it('getPublic não anexa Authorization nem envia header de bypass', async () => {
    instalarAdapter({ 'GET /api/v1/countries': () => [200, { countries: [] }] }, registro)

    await apiClient.getPublic('/api/v1/countries')

    const headers = registro[0].headers as Record<string, unknown>
    expect(headers.Authorization).toBeUndefined()
    expect(headers['X-Skip-Auth']).toBeUndefined()
  })
})
