import type { QueryClient } from '@tanstack/react-query'
import { assertValidQueryKey, isValidQueryKey } from './keys'

// app-shell-navigation 1.3 (D9) — o guard de forma de key. Assina o queryCache e,
// a cada query registrada, valida a forma. Em DEV e em teste LANÇA (a key
// ofensora na mensagem) para o erro aparecer no primeiro `useQuery(['projects'])`
// mal formado; em produção só REPORTA ao rastreio, sem derrubar o app.
//
// Sem isto, seis capacidades de tela inventariam seis convenções de estado de
// servidor e o D6 (realtime) ficaria sem alvo de invalidação.
function isStrict(): boolean {
  try {
    const env = (import.meta as unknown as { env?: { MODE?: string; DEV?: boolean } }).env
    return env?.MODE === 'test' || env?.DEV === true
  } catch {
    return false
  }
}

export function installQueryKeyGuard(client: QueryClient, report: (msg: string) => void = console.error): () => void {
  const strict = isStrict()
  return client.getQueryCache().subscribe((event) => {
    if (event.type !== 'added') return
    const key = event.query.queryKey
    if (isValidQueryKey(key)) return
    const msg = `query key fora da convenção D9 (['ws', wsId, …]): ${JSON.stringify(key)}`
    if (strict) throw new Error(msg)
    report(msg)
  })
}

export { assertValidQueryKey }
