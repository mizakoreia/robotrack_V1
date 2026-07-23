// Gatilhos de drenagem (offline-pwa 4.3). A fila tenta drenar quando: a rede
// volta (`online`), a aba ganha foco (`focus`), a aba fica visível
// (`visibilitychange`), e a cada 30s. TODOS passam pela mesma sonda de saúde
// (dentro do `run`, que chama `drainQueue` → `probe`), então "associado ao Wi-Fi
// sem rota de saída" custa uma sonda, não uma enxurrada de requisições.

export interface TriggerDeps {
  run: () => void | Promise<void>
  intervalMs?: number
  win?: Pick<Window, 'addEventListener' | 'removeEventListener'>
  doc?: Pick<Document, 'addEventListener' | 'removeEventListener' | 'visibilityState'>
  setInterval?: (cb: () => void, ms: number) => number
  clearInterval?: (id: number) => void
}

export function installDrainTriggers(deps: TriggerDeps): () => void {
  const win = deps.win ?? window
  const doc = deps.doc ?? document
  const setIntervalFn = deps.setInterval ?? ((cb, ms) => window.setInterval(cb, ms))
  const clearIntervalFn = deps.clearInterval ?? ((id) => window.clearInterval(id))
  const intervalMs = deps.intervalMs ?? 30_000

  const run = () => {
    void deps.run()
  }
  const onVisible = () => {
    if (doc.visibilityState === 'visible') run()
  }

  win.addEventListener('online', run)
  win.addEventListener('focus', run)
  doc.addEventListener('visibilitychange', onVisible)
  const timer = setIntervalFn(run, intervalMs)

  return () => {
    win.removeEventListener('online', run)
    win.removeEventListener('focus', run)
    doc.removeEventListener('visibilitychange', onVisible)
    clearIntervalFn(timer)
  }
}
