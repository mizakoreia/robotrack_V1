import { describe, expect, it } from 'vitest'
import { computeMenuPosition, type Rect } from '../position'

// app-shell-navigation 3.2 (D-C) — a medição prévia: sobe/desce pelo espaço,
// alinha à direita no estouro, e limita a altura com rolagem quando não cabe.
function rect(p: Partial<Rect>): Rect {
  return { top: 0, left: 0, right: 0, bottom: 0, width: 0, height: 0, ...p }
}

describe('computeMenuPosition (D-C)', () => {
  const vp = { width: 1000, height: 800 }

  it('gatilho no topo, menu cabe abaixo → abre para BAIXO', () => {
    const p = computeMenuPosition(rect({ top: 40, left: 100, right: 200, bottom: 64 }), { width: 160, height: 220 }, vp)
    expect(p.placement).toBe('down')
    expect(p.top).toBe(64 + 4)
  })

  it('gatilho perto do rodapé → abre para CIMA com top >= 8', () => {
    const p = computeMenuPosition(rect({ top: 760, left: 100, right: 200, bottom: 780 }), { width: 160, height: 220 }, vp)
    expect(p.placement).toBe('up')
    expect(p.top).toBeGreaterThanOrEqual(8)
  })

  it('menu maior que a viewport → limita a altura (rolagem interna)', () => {
    const p = computeMenuPosition(rect({ top: 300, left: 100, right: 200, bottom: 320 }), { width: 160, height: 900 }, vp)
    expect(p.maxHeight).toBeLessThan(900)
    expect(p.maxHeight).toBeGreaterThan(0)
  })

  it('estouro à direita → alinha à DIREITA (borda direita no gatilho)', () => {
    const p = computeMenuPosition(rect({ top: 40, left: 920, right: 980, bottom: 64 }), { width: 200, height: 100 }, vp)
    expect(p.align).toBe('right')
    expect(p.left).toBe(980 - 200)
  })

  it('sem estouro → alinha à ESQUERDA no gatilho', () => {
    const p = computeMenuPosition(rect({ top: 40, left: 100, right: 160, bottom: 64 }), { width: 200, height: 100 }, vp)
    expect(p.align).toBe('left')
    expect(p.left).toBe(100)
  })
})
