import { describe, expect, it } from 'vitest'
import { readFileSync } from 'node:fs'
import { join } from 'node:path'

// design-system 7.2/7.3/7.4/7.5 (D-DS-6) — as três camadas e degradações no CSS,
// os keyframes de motion na config, e a garantia de que a luz é DECORAÇÃO, não
// informação (não altera os tokens de texto/fundo, então o contraste é idêntico
// com a luz ligada ou com data-glow="off").
const CSS = readFileSync(join(__dirname, '../src/styles/globals.css'), 'utf8')
const TW = readFileSync(join(__dirname, '../tailwind.config.js'), 'utf8')

describe('as três camadas e degradações (7.2/7.3)', () => {
  it('declara .ambient, .glass-sheen::before e .glass::after', () => {
    expect(CSS).toMatch(/\.ambient\s*\{/)
    expect(CSS).toMatch(/\.glass-sheen::before\s*\{/)
    expect(CSS).toMatch(/\.glass::after\s*\{/)
  })

  it('as camadas resolvem do mesmo ponto (background-attachment: fixed)', () => {
    const ambient = CSS.slice(CSS.indexOf('.ambient {'), CSS.indexOf('}', CSS.indexOf('.ambient {')))
    expect(ambient).toMatch(/background-attachment:\s*fixed/)
  })

  it('data-glow="off" desliga TUDO, inclusive o halo', () => {
    expect(CSS).toMatch(/\[data-glow='off'\]\s+\.ambient/)
  })

  it('movimento reduzido congela a luz (sem transição) mas NÃO a remove', () => {
    const idx = CSS.indexOf('reduced-motion: reduce')
    // limita ao @media (antes da regra [data-glow='off'], que aí SIM esconde)
    const block = CSS.slice(idx, CSS.indexOf("[data-glow='off']", idx))
    expect(block).toMatch(/\.ambient\s*\{\s*transition:\s*none/)
    // dentro do @media, a .ambient não é escondida (mudaria a leitura, não só o movimento)
    expect(block).not.toMatch(/\.ambient[^}]*(display:\s*none|opacity:\s*0)/)
  })
})

describe('keyframes de motion (7.4)', () => {
  it('declara viewEnter/menuIn/modalPop/successPulse e as animações', () => {
    ;['viewEnter', 'menuIn', 'modalPop', 'successPulse'].forEach((k) => expect(TW).toMatch(new RegExp(`${k}:`)))
    ;['view-enter', 'menu-in', 'modal-pop', 'success-pulse'].forEach((a) => expect(TW).toContain(`'${a}':`))
  })

  it('nenhuma cubic-bezier tem componente y fora de [0,1] (sem bounce)', () => {
    const beziers = [...TW.matchAll(/cubic-bezier\(([^)]+)\)/g)].map((m) => m[1].split(',').map(Number))
    expect(beziers.length).toBeGreaterThan(0)
    beziers.forEach(([, y1, , y2]) => {
      expect(y1).toBeGreaterThanOrEqual(0)
      expect(y1).toBeLessThanOrEqual(1)
      expect(y2).toBeGreaterThanOrEqual(0)
      expect(y2).toBeLessThanOrEqual(1)
    })
  })
})

describe('a luz é decoração, não informação (7.5)', () => {
  it('a .ambient não altera nenhum token de texto/fundo (contraste idêntico com glow on/off)', () => {
    const ambient = CSS.slice(CSS.indexOf('.ambient {'), CSS.indexOf('}', CSS.indexOf('.ambient {')))
    expect(ambient).not.toMatch(/--text-main|--text-muted|--bg-main|--bg-panel/)
    // só usa accent a baixo alpha (halo), nada que carregue leitura
    expect(ambient).toMatch(/--accent/)
  })
})
