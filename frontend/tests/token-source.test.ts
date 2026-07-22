import { describe, expect, it, vi, beforeEach } from 'vitest'
import { readFileSync } from 'node:fs'
import { join } from 'node:path'

// app-shell-navigation 2.1–2.4 (D-E) — o token é fonte única (authStore); o
// client.ts não lê o armazenamento do navegador; sair descarta o cache; e a
// migração de boot importa as chaves legadas do template e as remove.

describe('fonte única do token (2.1)', () => {
  it('client.ts não contém a string localStorage', () => {
    const src = readFileSync(join(__dirname, '../src/lib/api/client.ts'), 'utf8')
    expect(src).not.toMatch(/localStorage/)
  })
})

describe('migração das chaves legadas (2.2)', () => {
  beforeEach(() => {
    vi.resetModules()
    localStorage.clear()
    sessionStorage.clear()
  })

  it('com access_token legado: hidrata o store e REMOVE as chaves legadas', async () => {
    localStorage.setItem('access_token', 'legacy-abc')
    const { useAuthStore } = await import('../src/store/authStore')
    expect(useAuthStore.getState().accessToken).toBe('legacy-abc')
    expect(localStorage.getItem('access_token')).toBeNull()
    expect(localStorage.getItem('token')).toBeNull()
  })

  it('sem chave legada: boot conclui sem token e sem erro', async () => {
    const { useAuthStore } = await import('../src/store/authStore')
    expect(useAuthStore.getState().accessToken).toBeNull()
  })

  it('segundo boot (já com sessão nova) não re-migra', async () => {
    localStorage.setItem('access_token', 'legacy-abc')
    await import('../src/store/authStore') // 1º boot migra
    vi.resetModules()
    localStorage.setItem('token', 'nao-deve-migrar') // chave legada nova aparece
    const { useAuthStore } = await import('../src/store/authStore')
    // já há sessão nova (robotrack.session): a legada é ignorada, não migrada
    expect(useAuthStore.getState().accessToken).toBe('legacy-abc')
    expect(localStorage.getItem('token')).toBe('nao-deve-migrar')
  })
})

describe('logout descarta cache (2.3)', () => {
  it('limpa o token e o cache do React Query', async () => {
    vi.resetModules()
    localStorage.clear()
    const { useAuthStore } = await import('../src/store/authStore')
    const { queryClient } = await import('../src/lib/queryClient')

    useAuthStore.getState().setSession('tok', null, { remember: true })
    queryClient.getQueryCache().build(queryClient, { queryKey: ['ws', 'betim', 'projects'], queryFn: async () => 1 })
    expect(queryClient.getQueryCache().getAll().length).toBeGreaterThan(0)

    useAuthStore.getState().logout()
    expect(useAuthStore.getState().accessToken).toBeNull()
    expect(queryClient.getQueryCache().getAll().length).toBe(0)
  })
})
