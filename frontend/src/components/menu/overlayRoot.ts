// app-shell-navigation 3.1 (D-C) — o contêiner dos overlays, filho DIRETO de
// <body>. Todo menu suspenso é renderizado aqui, fora da área de conteúdo
// rolável: um `position: absolute` dentro dela seria recortado por
// `overflow-y: auto`. Criado sob demanda, uma vez.
const OVERLAY_ID = 'rt-overlays'

export function getOverlayRoot(): HTMLElement {
  let el = document.getElementById(OVERLAY_ID)
  if (!el) {
    el = document.createElement('div')
    el.id = OVERLAY_ID
    document.body.appendChild(el)
  }
  return el
}
