import { describe, expect, it } from 'vitest'
import { readdirSync, readFileSync, statSync } from 'node:fs'
import { join } from 'node:path'

// design-system 3.3 (§5.1, D-DS-8) — ZERO emoji na interface. Varre
// src/**/*.{ts,tsx} por codepoints de `Emoji_Presentation` e reprova nomeando
// arquivo, linha e codepoint. Um `<span>✅ Concluído</span>` colado num badge
// falha com U+2705, em vez de ser o primeiro emoji que abre a porta para os
// próximos. Os quatro glifos do relatório A4 (✓ ◐ ○ —) são exceção do módulo de
// glifos de commissioning-report — allow-list por caminho (vazia por ora).
const EMOJI = /\p{Emoji_Presentation}/u
const ALLOW_PATHS: string[] = [] // ex.: 'src/features/report/glyphs' (A4)

function scan(dir: string, out: string[]) {
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry)
    if (statSync(full).isDirectory()) {
      if (entry !== 'node_modules') scan(full, out)
      continue
    }
    if (!/\.(ts|tsx)$/.test(entry)) continue
    if (full.includes('__tests__') || full.endsWith('no-emoji.test.ts')) continue
    if (ALLOW_PATHS.some((p) => full.includes(p))) continue

    readFileSync(full, 'utf8')
      .split('\n')
      .forEach((line, i) => {
        for (const ch of line) {
          if (EMOJI.test(ch)) {
            out.push(`${full}:${i + 1} U+${ch.codePointAt(0)!.toString(16).toUpperCase()}`)
          }
        }
      })
  }
}

describe('zero emoji na interface (D-DS-8)', () => {
  it('nenhum codepoint Emoji_Presentation em src', () => {
    const offenders: string[] = []
    scan(join(__dirname, '../src'), offenders)
    expect(offenders, `emoji encontrado (use o sprite de ícones):\n${offenders.join('\n')}`).toEqual([])
  })
})
