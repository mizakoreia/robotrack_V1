// design-system 7.1 (§5.1, D-DS-6) — a luz ambiente: UMA fonte em coordenadas de
// viewport (`--lx`/`--ly`), escrita SÓ no elemento raiz, com throttle de ~32ms.
//
// MODO DE FALHA: escrever a cada `pointermove` (60fps) invalida cada superfície de
// vidro duas vezes mais que o necessário e a inércia da luz não esconde mais o
// custo. A 32ms (≈30fps), 60 eventos em 1000ms produzem no máximo ~32 escritas.
//
// Gate por ponteiro FINO (D-DS-6): no toque não há luz que siga o dedo, então
// nem registramos o listener — zero custo no celular de galpão.
const THROTTLE_MS = 32

export function initAmbient(root: HTMLElement = document.documentElement, win: Window = window): () => void {
  const mq = win.matchMedia?.('(hover: hover) and (pointer: fine)')
  if (!mq || !mq.matches) return () => {}
  // Sob movimento reduzido, a luz CONGELA na posição de repouso: não registramos
  // o listener (as três camadas seguem pintadas pelo CSS no --lx/--ly inicial).
  if (win.matchMedia?.('(prefers-reduced-motion: reduce)')?.matches) return () => {}

  let last = -Infinity
  function onMove(e: PointerEvent) {
    const now = performance.now()
    if (now - last < THROTTLE_MS) return
    last = now
    root.style.setProperty('--lx', `${e.clientX}px`)
    root.style.setProperty('--ly', `${e.clientY}px`)
  }

  win.addEventListener('pointermove', onMove as EventListener)
  return () => win.removeEventListener('pointermove', onMove as EventListener)
}
