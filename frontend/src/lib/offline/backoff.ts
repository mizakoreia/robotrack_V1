// Backoff da drenagem (offline-pwa 5.2 / D7-5). `min(2^attempts × 1s, 5min)` com
// jitter de ±20%. Teto de 8 tentativas retryable → quarentena ("esgotado"): sem o
// teto, um 500 permanente do servidor vira um laço de reenvio que drena a bateria
// no chão de fábrica.

export const MAX_RETRY_ATTEMPTS = 8
const CEILING_MS = 5 * 60 * 1000 // 5 min

export function backoffMs(attempts: number, random: () => number = Math.random): number {
  const base = Math.min(2 ** attempts * 1000, CEILING_MS)
  const jitter = base * 0.2 * (random() * 2 - 1) // ±20%
  return Math.max(0, Math.round(base + jitter))
}

export function attemptsExhausted(attempts: number): boolean {
  return attempts >= MAX_RETRY_ATTEMPTS
}
