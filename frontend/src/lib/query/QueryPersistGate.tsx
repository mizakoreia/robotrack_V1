import { useEffect, useState, type ReactNode } from 'react'
import { queryClient } from '../queryClient'
import { restoreQueryCache, startQueryPersist } from './persist'

// Segura a árvore ATÉ o cache de leitura ser reidratado do IndexedDB, para as
// queries não renderizarem o estado de erro/vazio por um frame antes de o snapshot
// chegar (offline-pwa, cache de leitura offline). `restoreQueryCache` resolve
// sempre e com timeout curto — IDB bloqueado não pendura o boot. Depois da
// reidratação, liga a persistência contínua. O fundo escuro do anti-FOUC cobre o
// intervalo (poucos ms); nada pisca.
export function QueryPersistGate({ children }: { children: ReactNode }) {
  const [ready, setReady] = useState(false)

  useEffect(() => {
    let active = true
    let stop: (() => void) | undefined
    void restoreQueryCache(queryClient).finally(() => {
      if (!active) return
      stop = startQueryPersist(queryClient)
      setReady(true)
    })
    return () => {
      active = false
      stop?.()
    }
  }, [])

  if (!ready) return null
  return <>{children}</>
}
