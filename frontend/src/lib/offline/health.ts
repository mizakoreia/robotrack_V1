import { API_URL } from '../api/client'

// Sonda de saúde (offline-pwa 4.3 / D7-4). `HEAD /api/v1/health` é o PORTEIRO da
// drenagem: um toque barato antes de disparar os envios, para que um Wi-Fi de
// galpão sem rota de saída (associado mas sem internet) produza UMA sonda e não 40
// requisições. Qualquer falha de rede ou status não-ok = servidor inalcançável.

export async function probeHealth(
  deps: { fetchImpl?: typeof fetch; baseUrl?: string; signal?: AbortSignal } = {},
): Promise<boolean> {
  const fetchImpl = deps.fetchImpl ?? (typeof fetch !== 'undefined' ? fetch : undefined)
  if (!fetchImpl) return false
  const baseUrl = deps.baseUrl ?? API_URL
  try {
    const res = await fetchImpl(`${baseUrl}/api/v1/health`, { method: 'HEAD', signal: deps.signal })
    return res.ok
  } catch {
    return false
  }
}
