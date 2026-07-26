import 'fake-indexeddb/auto'
import { describe, it, expect, beforeEach } from 'vitest'
import { IDBFactory } from 'fake-indexeddb'
import { QueryClient } from '@tanstack/react-query'
import { restoreQueryCache, persistQueryCacheNow, purgeQueryCache, _resetPersistDbSingleton } from '../persist'
import { qk } from '../keys'
import { useAuthStore } from '../../../store/authStore'

// offline-pwa (cache de leitura offline) — o persister desidrata o cache do React
// Query para IndexedDB e o reidrata no boot, para telas já vistas online abrirem
// OFFLINE com DADOS em vez do estado de erro. Estes casos travam o contrato:
//   - round-trip: salvar num client, reidratar noutro → o dado volta;
//   - escopo de SESSÃO: token diferente → o snapshot é DESCARTADO (não vaza entre
//     usuários no dispositivo); sem token → nada reidrata;
//   - exclusões: `report` (documento inteiro-ou-nada) e `search` (transitória) não
//     são persistidos.

function login(token: string) {
  useAuthStore.setState({ isAuthenticated: true, accessToken: token, user: null })
}
function logout() {
  useAuthStore.setState({ isAuthenticated: false, accessToken: null, user: null })
}

function freshClient() {
  return new QueryClient({ defaultOptions: { queries: { gcTime: 1000 * 60 * 60 } } })
}

beforeEach(async () => {
  // IndexedDB limpo por caso + singleton do persister reaberto contra a factory nova.
  ;(globalThis as unknown as { indexedDB: IDBFactory }).indexedDB = new IDBFactory()
  _resetPersistDbSingleton()
  logout()
})

describe('persister do cache de leitura', () => {
  it('round-trip: dado salvo por uma sessão reidrata noutro client da MESMA sessão', async () => {
    login('token-A')
    const a = freshClient()
    a.setQueryData(qk.overview('ws1'), { projects: [{ id: 'p1', name: 'Linha 1' }], counts: {} })
    await persistQueryCacheNow(a)

    const b = freshClient()
    await restoreQueryCache(b)
    expect(b.getQueryData(qk.overview('ws1'))).toEqual({
      projects: [{ id: 'p1', name: 'Linha 1' }],
      counts: {},
    })
  })

  it('escopo de sessão: token DIFERENTE no boot → snapshot descartado, nada reidrata', async () => {
    login('token-A')
    const a = freshClient()
    a.setQueryData(qk.overview('ws1'), { projects: [{ id: 'p1' }] })
    await persistQueryCacheNow(a)

    // Outra pessoa loga na mesma aba.
    login('token-B')
    const b = freshClient()
    await restoreQueryCache(b)
    expect(b.getQueryData(qk.overview('ws1'))).toBeUndefined()

    // E o snapshot foi de fato purgado: nem a própria sessão A o recupera depois.
    login('token-A')
    const c = freshClient()
    await restoreQueryCache(c)
    expect(c.getQueryData(qk.overview('ws1'))).toBeUndefined()
  })

  it('deslogado no boot → não reidrata (e purga o que houver)', async () => {
    login('token-A')
    const a = freshClient()
    a.setQueryData(qk.overview('ws1'), { projects: [] })
    await persistQueryCacheNow(a)

    logout()
    const b = freshClient()
    await restoreQueryCache(b)
    expect(b.getQueryData(qk.overview('ws1'))).toBeUndefined()
  })

  it('não persiste report nem search; persiste as demais', async () => {
    login('token-A')
    const a = freshClient()
    a.setQueryData(qk.overview('ws1'), { projects: [{ id: 'p1' }] })
    a.setQueryData(qk.report('ws1', 'all'), { doc: 'inteiro' })
    a.setQueryData(qk.search('ws1', 'abc'), { hits: [] })
    await persistQueryCacheNow(a)

    const b = freshClient()
    await restoreQueryCache(b)
    expect(b.getQueryData(qk.overview('ws1'))).toEqual({ projects: [{ id: 'p1' }] })
    expect(b.getQueryData(qk.report('ws1', 'all'))).toBeUndefined()
    expect(b.getQueryData(qk.search('ws1', 'abc'))).toBeUndefined()
  })

  it('purgeQueryCache apaga o snapshot', async () => {
    login('token-A')
    const a = freshClient()
    a.setQueryData(qk.overview('ws1'), { projects: [{ id: 'p1' }] })
    await persistQueryCacheNow(a)
    await purgeQueryCache()

    const b = freshClient()
    await restoreQueryCache(b)
    expect(b.getQueryData(qk.overview('ws1'))).toBeUndefined()
  })
})
