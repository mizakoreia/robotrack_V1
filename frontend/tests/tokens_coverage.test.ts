import { describe, expect, it } from 'vitest'
import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import tokens from '../src/styles/tokens.json'

// design-system 2.4 (§5.1, D-DS-2) — a cobertura que impede o contraste medido de
// virar ficção. Sem isso, um par novo entra na tela sem nunca passar por 2.3, ou
// um token muda no globals.css e a tabela de tokens.json continua afirmando o
// valor antigo. Aqui: (a) as 5 famílias × 2 temas estão na tabela; (b) cada cor
// da tabela BATE com o token real do globals.css; (c) a config do Tailwind mantém
// a restrição de namespace (nenhum `text-success`/`bg-success-ink` emitível).

const CSS = readFileSync(join(__dirname, '../src/styles/globals.css'), 'utf8')
const TW = readFileSync(join(__dirname, '../tailwind.config.js'), 'utf8')

function block(selector: string): string {
  const start = CSS.indexOf(`${selector} {`)
  const open = CSS.indexOf('{', start)
  return CSS.slice(open + 1, CSS.indexOf('\n}', open))
}
function tokenHex(theme: string, name: string): string {
  // Tokens não sobrescritos no claro (status cheio same-both) vêm do :root.
  const re = new RegExp(`--${name}:\\s*([^;]+);`)
  const primary = theme === 'dark' ? ':root' : '.light'
  const m = block(primary).match(re) || block(':root').match(re)
  if (!m) throw new Error(`--${name} ausente em ${theme} e :root`)
  const t = m[1].replace(/\/\*.*$/, '').trim()
  const hm = t.match(/^(\d+)\s+(\d+)%\s+(\d+)%$/)
  if (!hm) throw new Error(`--${name} não é tripla: ${t}`)
  const h = +hm[1] / 360
  const s = +hm[2] / 100
  const l = +hm[3] / 100
  const hue = (p: number, q: number, x: number) => {
    if (x < 0) x += 1
    if (x > 1) x -= 1
    if (x < 1 / 6) return p + (q - p) * 6 * x
    if (x < 1 / 2) return q
    if (x < 2 / 3) return p + (q - p) * (2 / 3 - x) * 6
    return p
  }
  let r: number
  let g: number
  let b: number
  if (s === 0) r = g = b = l
  else {
    const q = l < 0.5 ? l * (1 + s) : l + s - l * s
    const p = 2 * l - q
    r = hue(p, q, h + 1 / 3)
    g = hue(p, q, h)
    b = hue(p, q, h - 1 / 3)
  }
  return `#${[r, g, b].map((v) => Math.round(v * 255).toString(16).padStart(2, '0')).join('')}`
}
function near(a: string, b: string): boolean {
  const ca = [1, 3, 5].map((i) => parseInt(a.replace('#', '').slice(i - 1, i + 1), 16))
  const cb = [1, 3, 5].map((i) => parseInt(b.replace('#', '').slice(i - 1, i + 1), 16))
  return ca.every((v, i) => Math.abs(v - cb[i]) <= 2)
}

describe('cobertura da tabela de tokens (D-DS-2)', () => {
  it('as 5 famílias de status estão na tabela nos dois temas', () => {
    const fam = ['success', 'warning', 'danger', 'accent', 'na']
    ;['light', 'dark'].forEach((tema) => {
      const nomes = tokens.pills.filter((p) => p.tema === tema).map((p) => p.name).sort()
      expect(nomes, `pílulas do tema ${tema}`).toEqual([...fam].sort())
    })
  })

  it('cada cor da tabela bate com o token real do globals.css', () => {
    tokens.pills.forEach((p) => {
      expect(near(p.full, tokenHex(p.tema, p.name)), `full ${p.name}/${p.tema}: ${p.full} vs token`).toBe(true)
      expect(near(p.fg, tokenHex(p.tema, `${p.name}-ink`)), `ink ${p.name}/${p.tema}: ${p.fg} vs token`).toBe(true)
    })
  })

  it('a config do Tailwind mantém a restrição de namespace (D-DS-2)', () => {
    const colorsBlock = TW.slice(TW.indexOf('colors: {'), TW.indexOf('backgroundColor: {'))
    // status full e ink NÃO podem estar em `colors` (senão text-success existiria)
    ;['success:', 'warning:', 'danger:', "'success-ink'", "'danger-ink'"].forEach((k) => {
      expect(colorsBlock.includes(k), `${k} não pode estar em colors (D-DS-2)`).toBe(false)
    })
    // cheia em backgroundColor, tinta em textColor
    const bgBlock = TW.slice(TW.indexOf('backgroundColor: {'), TW.indexOf('textColor: {'))
    const textBlock = TW.slice(TW.indexOf('textColor: {'), TW.indexOf('borderColor: {'))
    expect(bgBlock).toMatch(/success:/)
    expect(bgBlock).toMatch(/'accent-solid'/)
    expect(textBlock).toMatch(/'success-ink'/)
    expect(textBlock).not.toMatch(/\bsuccess:/) // tinta não é cheia
  })
})
