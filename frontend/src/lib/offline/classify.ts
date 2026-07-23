import type { MutationMethod } from './types'

// Classificação de resposta da drenagem (offline-pwa 5.1 / D7-5). A máquina de
// estados do item vive aqui: cada resposta cai em exatamente uma classe, e a
// classe decide entre retry, falha permanente, conflito e pausa por auth.

export type Decision =
  | { kind: 'success' }
  | { kind: 'retry'; countsAttempt: boolean } // backoff; countsAttempt=false para erro de rede
  | { kind: 'auth' } // 401 — pausa a fila inteira, sem consumir tentativa
  | { kind: 'conflict' } // 409 lock_version — failed + reconciliação, sem retry
  | { kind: 'permanent' } // 403/404/422 — failed, sem retry

const RETRYABLE_STATUS = new Set([408, 429, 500, 502, 503, 504])

export function classifyResponse(input: {
  status: number
  networkError?: boolean
  method: MutationMethod
}): Decision {
  // Erro de rede / fetch rejeitado: retry SEM contar tentativa contra o teto —
  // "sem rota de saída" não é culpa do item.
  if (input.networkError || input.status === 0) return { kind: 'retry', countsAttempt: false }

  const { status, method } = input

  if (status >= 200 && status < 300) return { kind: 'success' }

  // DELETE de um uuid já removido responde 404, e o efeito desejado (não existe)
  // já foi atingido: SUCESSO para fins de fila (D7-6), senão a quarentena enche de
  // exclusões já satisfeitas.
  if (method === 'DELETE' && status === 404) return { kind: 'success' }

  if (status === 401) return { kind: 'auth' }
  if (status === 409) return { kind: 'conflict' }
  if (status === 403 || status === 404 || status === 422) return { kind: 'permanent' }
  if (RETRYABLE_STATUS.has(status)) return { kind: 'retry', countsAttempt: true }

  // Desconhecido (ex.: 501, 505): permanente por segurança — nunca girar bateria
  // num status que não sabemos ser transitório.
  return { kind: 'permanent' }
}
