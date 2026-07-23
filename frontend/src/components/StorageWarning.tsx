import { useState } from 'react'
import { probeStorageLevel, safeStorage, type StorageLevel } from '@/lib/safeStorage'

// Aviso de armazenamento bloqueado (offline-pwa 1.3 / D7-11). Persistente e
// dispensável-POR-SESSÃO: aparece em `session-only` e `memory-only`, some quando
// o usuário fecha, e não volta na mesma sessão. Em `persistent` (o caminho feliz)
// não renderiza nada.
//
// As duas redações são LEI do D7-11:
//   session-only → "...a sessão não vai persistir ao fechar."
//   memory-only  → idem + "e alterações feitas sem conexão não serão salvas."
//
// A dispensa mora em sessionStorage via safeStorage: em `memory-only` isso cai
// para memória e o aviso reaparece após um reload — o que é honesto, já que
// nesse nível nada sobrevive a reload de qualquer modo.

const DISMISS_KEY = 'robotrack.storage_warning_dismissed'

const BASE = 'Seu navegador está bloqueando o armazenamento. Você pode usar o RoboTrack normalmente, mas a sessão não vai persistir ao fechar'
const MEMORY_SUFFIX = ', e alterações feitas sem conexão não serão salvas'

function messageFor(level: StorageLevel): string | null {
  if (level === 'persistent') return null
  return level === 'memory-only' ? `${BASE}${MEMORY_SUFFIX}.` : `${BASE}.`
}

export function StorageWarning() {
  const level = probeStorageLevel()
  const [dismissed, setDismissed] = useState(() => safeStorage.get('session', DISMISS_KEY) === '1')

  const message = messageFor(level)
  if (!message || dismissed) return null

  const dismiss = () => {
    safeStorage.set('session', DISMISS_KEY, '1')
    setDismissed(true)
  }

  return (
    <div
      role="status"
      className="flex items-start gap-3 border-b border-warning/40 bg-warning/10 px-4 py-2 text-sm text-text"
    >
      <span className="flex-1">{message}</span>
      <button
        type="button"
        onClick={dismiss}
        aria-label="Dispensar aviso"
        className="shrink-0 rounded px-2 py-0.5 text-text-muted hover:text-text"
      >
        Dispensar
      </button>
    </div>
  )
}
