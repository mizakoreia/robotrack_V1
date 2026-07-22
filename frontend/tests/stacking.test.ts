import { describe, expect, it } from 'vitest'
import { readdirSync, readFileSync, statSync } from 'node:fs'
import { join } from 'node:path'

// design-system 4.1 (§5.1, D-DS-4) — o empilhamento semântico e a proibição do
// z-index literal. `z-index: 999` ou `z-[9999]` fora do globals.css falha o CI;
// sem isso o próximo conflito de empilhamento vira 9999 e a escala morre.
const CSS = readFileSync(join(__dirname, '../src/styles/globals.css'), 'utf8')
const TW = readFileSync(join(__dirname, '../tailwind.config.js'), 'utf8')
const LEVELS: Record<string, string> = {
  ambient: '0',
  content: '1',
  sticky: '20',
  sidebar: '30',
  dropdown: '60',
  modal: '90',
  login: '200',
}

function scan(dir: string, re: RegExp, out: string[]) {
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry)
    if (statSync(full).isDirectory()) {
      if (entry !== 'node_modules') scan(full, re, out)
      continue
    }
    if (!/\.(ts|tsx|css)$/.test(entry)) continue
    if (full.endsWith('globals.css')) continue // a fonte dos tokens é permitida
    if (full.includes('__tests__') || full.endsWith('stacking.test.ts')) continue
    readFileSync(full, 'utf8')
      .split('\n')
      .forEach((line, i) => {
        if (re.test(line)) out.push(`${full.replace(join(__dirname, '..'), '.')}:${i + 1}: ${line.trim()}`)
      })
  }
}

describe('empilhamento semântico (D-DS-4)', () => {
  it('os 7 níveis existem como custom property com os valores canônicos', () => {
    Object.entries(LEVELS).forEach(([name, value]) => {
      const m = CSS.match(new RegExp(`--z-${name}:\\s*(\\d+);`))
      expect(m?.[1], `--z-${name}`).toBe(value)
    })
  })

  it('a escala está exposta em theme.extend.zIndex do Tailwind', () => {
    const z = TW.slice(TW.indexOf('zIndex: {'), TW.indexOf('}', TW.indexOf('zIndex: {')))
    Object.keys(LEVELS).forEach((name) => expect(z, `zIndex.${name}`).toMatch(new RegExp(`\\b${name}:`)))
  })

  it('nenhum z-[N] arbitrário nem z-index literal fora do globals.css', () => {
    const offenders: string[] = []
    scan(join(__dirname, '../src'), /z-\[\d+\]|z-index:\s*\d+/, offenders)
    expect(offenders, `z-index literal (use z-modal/z-dropdown/…):\n${offenders.join('\n')}`).toEqual([])
  })
})
