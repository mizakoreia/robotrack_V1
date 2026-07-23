// Sentry do cliente (delivery-and-observability 4.2). SEM dependência dura de
// @sentry/react no bundle: a função de init é INJETADA (o wiring real + o upload
// de source maps entram no CI/deploy). Aqui mora a lógica testável — a release
// atrelada ao hash do build e o guarda que mantém tudo desligado sem DSN.
//
// Source maps: `vite.config` emite `.map`, mas eles são ENVIADOS ao Sentry no CI e
// NÃO servidos publicamente (o CDN não expõe `.map`) — senão o stack legível
// vazaria a fonte.

export interface SentryClientConfig {
  dsn: string
  release: string | undefined
  environment: string
}

type SentryInit = (config: SentryClientConfig) => void

interface Env {
  VITE_SENTRY_DSN?: string
  VITE_SENTRY_RELEASE?: string
  MODE?: string
}

export function sentryConfig(env: Env): SentryClientConfig | null {
  const dsn = env.VITE_SENTRY_DSN
  if (!dsn || env.MODE === 'test') return null // sem DSN (ou em teste) = desligado
  return {
    dsn,
    release: env.VITE_SENTRY_RELEASE, // hash do build, atrelada no CI
    environment: env.MODE ?? 'production',
  }
}

// Inicializa o Sentry SE houver DSN e um init injetado. No-op caso contrário.
export function initClientSentry(init: SentryInit | undefined, env: Env): boolean {
  const config = sentryConfig(env)
  if (!config || !init) return false
  init(config)
  return true
}
