import { useEffect, useRef } from 'react'
import { useRealtimeStore } from '@/store/realtimeStore'
import { announce } from '@/store/liveRegionStore'

// quality-and-accessibility 5.1 — roteia o TRANSPORTE de tempo real para `#rt-status`
// (região persistente), fechando o buraco do `ConnectionIndicator`, que só monta seu
// próprio nó quando degrada (região inserida com texto = não anunciada). Aqui a
// mudança de estado empurra o texto para uma região que já existe. Não anuncia o
// estado inicial (só transições), para não falar "conectado" ao abrir a página.
const LABEL: Record<string, string> = {
  offline: 'Sem conexão',
  degraded: 'Atualizando periodicamente',
  live: 'Conexão restabelecida',
  connecting: '',
}

export function LiveAnnouncer() {
  const transport = useRealtimeStore((s) => s.transport)
  const previous = useRef<string | null>(null)

  useEffect(() => {
    if (previous.current !== null && previous.current !== transport) {
      const msg = LABEL[transport] ?? ''
      if (msg) announce('status', msg)
    }
    previous.current = transport
  }, [transport])

  return null
}
