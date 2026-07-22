// app-shell-navigation 3.2 (D-C) — a MEDIÇÃO PRÉVIA como função pura. O menu é
// posicionado a partir do retângulo do gatilho e do TAMANHO medido do menu (com
// `visibility: hidden`, antes de pintar). Decide subir ou descer pelo espaço
// disponível, alinha à esquerda ou à direita quando estouraria a borda, e limita
// a altura com rolagem interna quando não cabe em lado nenhum. jsdom não faz
// layout, então a lógica vive aqui, testável com retângulos mockados.
export interface Rect {
  top: number
  left: number
  right: number
  bottom: number
  width: number
  height: number
}

export interface Viewport {
  width: number
  height: number
}

export interface MenuPosition {
  top: number
  left: number
  placement: 'up' | 'down'
  align: 'left' | 'right'
  maxHeight: number
}

const GAP = 4
const MARGIN = 8

export function computeMenuPosition(trigger: Rect, menuSize: { width: number; height: number }, viewport: Viewport): MenuPosition {
  const spaceBelow = viewport.height - trigger.bottom - GAP
  const spaceAbove = trigger.top - GAP

  let placement: 'up' | 'down'
  if (menuSize.height <= spaceBelow) placement = 'down'
  else if (menuSize.height <= spaceAbove) placement = 'up'
  else placement = spaceBelow >= spaceAbove ? 'down' : 'up' // não cabe em nenhum: o maior lado, com rolagem

  const available = placement === 'down' ? spaceBelow : spaceAbove
  const maxHeight = Math.max(0, Math.min(menuSize.height, available - MARGIN))
  const top =
    placement === 'down'
      ? trigger.bottom + GAP
      : Math.max(MARGIN, trigger.top - GAP - maxHeight)

  let align: 'left' | 'right' = 'left'
  let left = trigger.left
  if (left + menuSize.width > viewport.width - MARGIN) {
    align = 'right'
    left = trigger.right - menuSize.width
  }
  left = Math.max(MARGIN, left)

  return { top, left, placement, align, maxHeight }
}
