import { useLiveRegionStore } from '@/store/liveRegionStore'

// quality-and-accessibility 5.1 (D-QA-4) — os três marcos de região viva, montados
// INCONDICIONALMENTE no shell e visualmente ocultos (`sr-only`). Ficam vazios até
// alguém chamar `announce(...)`; como o nó já existe, a MUDANÇA de texto é anunciada.
// `status`/`notifications` são `polite` (não interrompem quem digita); `alerts` é
// `assertive` + `role="alert"` (perda de acesso tem de interromper).
export function LiveRegions() {
  const status = useLiveRegionStore((s) => s.status)
  const notifications = useLiveRegionStore((s) => s.notifications)
  const alerts = useLiveRegionStore((s) => s.alerts)

  return (
    <>
      <div id="rt-status" className="sr-only" role="status" aria-live="polite" aria-atomic="true">
        {status}
      </div>
      <div id="rt-notifications" className="sr-only" aria-live="polite">
        {notifications}
      </div>
      <div id="rt-alerts" className="sr-only" role="alert" aria-live="assertive">
        {alerts}
      </div>
    </>
  )
}
