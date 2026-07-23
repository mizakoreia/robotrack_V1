import { toast } from 'sonner'

// Registro do service worker (offline-pwa 2.4 / D7-3). SÓ em produção: em dev o
// HMR do Vite e o SW brigam (o SW serviria o bundle velho do cache). O worker é
// progressivo — se o registro falhar, o app continua funcionando online.
//
// `controllerchange` dispara quando um SW NOVO assume o controle da página: é o
// sinal de "deploy aconteceu enquanto esta aba estava aberta". Em vez de deixar a
// aba rodando código antigo em silêncio, avisamos e oferecemos recarregar.
//
// HANDOFF (delivery-and-observability): o servidor de assets DEVE servir `/sw.js`
// com `Cache-Control: no-cache, must-revalidate`. Sem isso o browser guarda o
// próprio sw.js por `max-age` e o deploy seguinte não é detectado. Não há server
// de assets no repo (Vite dev só) — a configuração vive no runbook daquela onda.

let refreshing = false

function notifyNewVersion(reload: () => void): void {
  toast('Nova versão disponível', {
    description: 'Recarregue para atualizar o RoboTrack.',
    action: { label: 'Recarregar', onClick: reload },
    duration: Infinity,
  })
}

export function registerServiceWorker(
  deps: {
    swContainer?: ServiceWorkerContainer | undefined
    isProd?: boolean
    reload?: () => void
    onLoad?: (cb: () => void) => void
  } = {},
): void {
  const container = deps.swContainer ?? (typeof navigator !== 'undefined' ? navigator.serviceWorker : undefined)
  const isProd = deps.isProd ?? import.meta.env.PROD
  const reload = deps.reload ?? (() => window.location.reload())
  const onLoad = deps.onLoad ?? ((cb) => window.addEventListener('load', cb))

  if (!container || !isProd) return

  container.addEventListener('controllerchange', () => {
    // Só a PRIMEIRA troca importa; sem o guard, um `reload()` que reprocessa o SW
    // dispararia o aviso de novo, em laço.
    if (refreshing) return
    refreshing = true
    notifyNewVersion(reload)
  })

  onLoad(() => {
    container.register('/sw.js').catch(() => {
      /* SW é progressivo: a falha de registro não pode quebrar o boot */
    })
  })
}

// Só para testes: reseta o guard de refresh entre casos.
export function resetServiceWorkerState(): void {
  refreshing = false
}
