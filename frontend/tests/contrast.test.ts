import { describe, expect, it } from 'vitest'
import tokens from '../src/styles/tokens.json'

// design-system 2.3 (§5.1, D-DS-2) — o teste de contraste MEDIDO. Recompõe cada
// par (pílula = status cheio composto sobre a superfície com o alpha do papel;
// base = texto sobre fundo; sólida = branco sobre a cor sólida), computa a razão
// de contraste WCAG 2.1 (luminância relativa) e reprova abaixo de 4.5:1 (corpo).
//
// É a rede contra a armadilha nº 1 do porte: trocar `--text-muted` do claro de
// #475569 (6.92:1) por #94a3b8 (2.28:1) derruba o par e o teste falha nomeando
// par, tema, valor medido e mínimo.

function channels(hex: string): [number, number, number] {
  const h = hex.replace('#', '')
  return [parseInt(h.slice(0, 2), 16), parseInt(h.slice(2, 4), 16), parseInt(h.slice(4, 6), 16)]
}

function relLuminance(hex: string): number {
  const lin = (c: number) => {
    const s = c / 255
    return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4
  }
  const [r, g, b] = channels(hex)
  return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
}

function ratio(a: string, b: string): number {
  const la = relLuminance(a)
  const lb = relLuminance(b)
  return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05)
}

// Composição alpha de `fg` sobre `bg` (a pílula tingida sobre a superfície).
function composite(fg: string, alpha: number, bg: string): string {
  const f = channels(fg)
  const b = channels(bg)
  const m = f.map((c, i) => Math.round(c * alpha + b[i] * (1 - alpha)))
  return `#${m.map((v) => v.toString(16).padStart(2, '0')).join('')}`
}

describe('contraste medido dos tokens (D-DS-2)', () => {
  tokens.pills.forEach((p) => {
    it(`pílula ${p.name} / ${p.tema}: tinta sobre a pílula composta ≥ ${p.min}:1`, () => {
      const bg = composite(p.full, p.alpha, p.surface)
      const r = ratio(p.fg, bg)
      expect(r, `${p.name}/${p.tema}: ${r.toFixed(2)}:1 (pílula ${bg}), mínimo ${p.min}:1`).toBeGreaterThanOrEqual(p.min)
    })
  })

  tokens.base.forEach((b) => {
    it(`base ${b.name} / ${b.tema}: texto sobre fundo ≥ ${b.min}:1`, () => {
      const r = ratio(b.fg, b.bg)
      expect(r, `${b.name}/${b.tema}: ${r.toFixed(2)}:1, mínimo ${b.min}:1`).toBeGreaterThanOrEqual(b.min)
    })
  })

  tokens.solid.forEach((s) => {
    it(`sólida ${s.name}: branco sobre a cor ≥ ${s.min}:1`, () => {
      const r = ratio(s.fg, s.bg)
      expect(r, `${s.name}: ${r.toFixed(2)}:1, mínimo ${s.min}:1`).toBeGreaterThanOrEqual(s.min)
    })
  })

  // q&a 4.1 — o contorno de foco (--ring) é elemento não-texto (piso 3:1) e tem de
  // ser visível sobre as DUAS superfícies de cada tema. #60a5fa (escuro) e #1d4ed8
  // (claro) ficam bem acima (≈6-7:1); abaixo de 3:1 é foco invisível sob luz de galpão.
  tokens.focus.forEach((s) => {
    it(`foco ${s.name}: contorno sobre a superfície ≥ ${s.min}:1`, () => {
      const r = ratio(s.fg, s.bg)
      expect(r, `${s.name}: ${r.toFixed(2)}:1, mínimo ${s.min}:1`).toBeGreaterThanOrEqual(s.min)
    })
  })
})
