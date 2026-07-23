import type { QueryClient } from '@tanstack/react-query'
import type { QueryKey } from './eventMap'

// realtime-collaboration 6.2/6.3 / D6.4 — o GATE de represamento. Uma invalidação
// só reverte a UI otimista se o servidor já incluir a escrita local; enquanto uma
// mutação da MESMA entidade está em voo (ou enfileirada offline), a invalidação
// espera. Assim um evento de TERCEIRO durante o POST em voo não faz a tela piscar
// 60→40→60: o refetch acontece depois, quando o valor do servidor já tem os 60.

// D7 (offline-pwa) ainda não existe → CONTRATO injetável, default vazio. A fila
// real chega com o offline-pwa e passa a represar por item pendente no IndexedDB.
export interface OfflinePendingProbe {
  hasPendingFor(kind: string, id: string): boolean
}
export const NO_OFFLINE_PENDING: OfflinePendingProbe = { hasPendingFor: () => false }

// Prefixo: `a` é prefixo de `b` (mesma subárvore de cache).
export function isPrefix(a: readonly unknown[], b: readonly unknown[]): boolean {
  if (a.length > b.length) return false
  for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return false
  return true
}
// Duas keys se INTERSECTAM se uma é prefixo da outra (ex.: invalidar
// `['ws',w,'robot',r]` intersecta a mutationKey `['ws',w,'robot',r,'tasks']`).
export function keysIntersect(a: QueryKey, b: QueryKey): boolean {
  return isPrefix(a, b) || isPrefix(b, a)
}

const ENTITY_KINDS = new Set(['project', 'cell', 'robot', 'task'])
// Entidade de uma key `['ws', w, <kind>, <id>, …]` para consultar a fila offline.
export function entityOf(key: QueryKey): { kind: string; id: string } | null {
  if (key.length >= 4 && typeof key[2] === 'string' && ENTITY_KINDS.has(key[2]) && typeof key[3] === 'string') {
    return { kind: key[2], id: key[3] }
  }
  return null
}

export class InvalidationGate {
  constructor(
    private readonly client: QueryClient,
    private readonly offline: OfflinePendingProbe = NO_OFFLINE_PENDING,
  ) {}

  private inFlightMutationKeys(): QueryKey[] {
    return this.client
      .getMutationCache()
      .getAll()
      .filter((m) => m.state.status === 'pending')
      .map((m) => m.options.mutationKey)
      .filter((k): k is QueryKey => Array.isArray(k))
  }

  isDammed(key: QueryKey): boolean {
    if (this.inFlightMutationKeys().some((mk) => keysIntersect(key, mk))) return true
    const ent = entityOf(key)
    return ent ? this.offline.hasPendingFor(ent.kind, ent.id) : false
  }

  // Notifica quando o cache de mutações muda (uma mutação assentou em sucesso OU
  // erro) — a fila re-avalia o represado. Um 409 de lock_version drena a fila em
  // vez de deixá-la presa para sempre.
  subscribeSettle(cb: () => void): () => void {
    return this.client.getMutationCache().subscribe(() => cb())
  }
}
