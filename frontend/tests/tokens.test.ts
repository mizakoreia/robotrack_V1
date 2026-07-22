import { describe, expect, it } from 'vitest'
import { readFileSync } from 'node:fs'
import { join } from 'node:path'

// design-system 1.4 (§5.1, D-DS-1) — verificação dos tokens canônicos nos dois
// temas. Lê o globals.css (fonte única) e afirma os valores de marca; se alguém
// embutir alpha num token de superfície, o modificador de opacidade do Tailwind
// multiplicaria em cima — por isso `--bg-panel` TEM de ser uma tripla de três
// componentes, sem `rgba(` e sem `/`.

const CSS = readFileSync(join(__dirname, '../src/styles/globals.css'), 'utf8')

// Extrai o corpo de um seletor de topo (`:root {...}` / `.light {...}`).
function block(selector: string): string {
  const start = CSS.indexOf(`${selector} {`)
  if (start < 0) throw new Error(`bloco ${selector} não encontrado`)
  const open = CSS.indexOf('{', start)
  return CSS.slice(open + 1, CSS.indexOf('\n}', open))
}

// Valor cru de um token dentro de um bloco (sem o comentário à direita).
function token(body: string, name: string): string {
  const m = body.match(new RegExp(`--${name}:\\s*([^;]+);`))
  if (!m) throw new Error(`token --${name} ausente`)
  return m[1].replace(/\/\*.*$/, '').trim()
}

function hslTripleToHex(triple: string): string {
  const m = triple.match(/^(\d+)\s+(\d+)%\s+(\d+)%$/)
  if (!m) throw new Error(`não é tripla HSL: "${triple}"`)
  const h = +m[1] / 360
  const s = +m[2] / 100
  const l = +m[3] / 100
  const hue = (p: number, q: number, t: number) => {
    if (t < 0) t += 1
    if (t > 1) t -= 1
    if (t < 1 / 6) return p + (q - p) * 6 * t
    if (t < 1 / 2) return q
    if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6
    return p
  }
  let r: number
  let g: number
  let b: number
  if (s === 0) {
    r = g = b = l
  } else {
    const q = l < 0.5 ? l * (1 + s) : l + s - l * s
    const p = 2 * l - q
    r = hue(p, q, h + 1 / 3)
    g = hue(p, q, h)
    b = hue(p, q, h - 1 / 3)
  }
  const to = (x: number) => Math.round(x * 255)
  return `#${[to(r), to(g), to(b)].map((v) => v.toString(16).padStart(2, '0')).join('')}`
}

function channels(hex: string): [number, number, number] {
  const h = hex.replace('#', '')
  return [parseInt(h.slice(0, 2), 16), parseInt(h.slice(2, 4), 16), parseInt(h.slice(4, 6), 16)]
}

// Igualdade de hex com tolerância de ±2/canal (arredondamento hex→HSL→hex).
function expectHexNear(actual: string, expected: string) {
  const a = channels(actual)
  const e = channels(expected)
  a.forEach((v, i) => expect(Math.abs(v - e[i]), `${actual} vs ${expected} canal ${i}`).toBeLessThanOrEqual(2))
}

describe('tokens canônicos (D-DS-1)', () => {
  const dark = block(':root')
  const light = block('.light')

  it('escuro (:root): bg-main #0a0f1d, text-main #f8fafc, accent #3b82f6', () => {
    expectHexNear(hslTripleToHex(token(dark, 'bg-main')), '#0a0f1d')
    expectHexNear(hslTripleToHex(token(dark, 'text-main')), '#f8fafc')
    expectHexNear(hslTripleToHex(token(dark, 'accent')), '#3b82f6')
  })

  it('claro (.light): bg-main #f1f5f9, text-main #0f172a, accent #2563eb', () => {
    expectHexNear(hslTripleToHex(token(light, 'bg-main')), '#f1f5f9')
    expectHexNear(hslTripleToHex(token(light, 'text-main')), '#0f172a')
    expectHexNear(hslTripleToHex(token(light, 'accent')), '#2563eb')
  })

  it('--bg-panel é tripla de 3 componentes, sem rgba( e sem /', () => {
    const v = token(dark, 'bg-panel')
    expect(v).not.toMatch(/rgba\(|\//)
    expect(v.split(/\s+/)).toHaveLength(3)
  })

  it('nenhum token de cor embute alpha (varredura do :root)', () => {
    const suspeitos = dark
      .split('\n')
      .filter((l) => /--(bg|text|accent|success|warning|danger|na|border|track)/.test(l) && /rgba\(|hsl\(|\/\s*[0-9.]/.test(l.replace(/\/\*.*/, '')))
    expect(suspeitos).toEqual([])
  })
})
