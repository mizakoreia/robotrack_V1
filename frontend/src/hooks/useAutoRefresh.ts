// Hook de autoatualização
// Executa uma função callback em intervalos configuráveis, com cancelamento seguro.
import { useEffect, useRef } from 'react'

export function useAutoRefresh(fn: () => Promise<void> | void, intervalMs = 30000) {
  const abortRef = useRef<AbortController | null>(null)
  const timerRef = useRef<any>(null)

  useEffect(() => {
    const run = async () => {
      try {
        await fn()
      } catch {}
    }

    run()
    try { if (timerRef.current) clearInterval(timerRef.current) } catch {}
    timerRef.current = setInterval(run, intervalMs)

    return () => {
      try { if (timerRef.current) clearInterval(timerRef.current) } catch {}
      if (abortRef.current) abortRef.current.abort()
    }
  }, [intervalMs])
}

