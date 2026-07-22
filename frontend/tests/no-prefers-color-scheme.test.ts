import { describe, expect, it } from 'vitest'
import { readdirSync, readFileSync, statSync } from 'node:fs'
import { join } from 'node:path'

// design-system 4.3 (§5.1, D-DS-3) — o guarda que protege a decisão de produto:
// o tema NÃO deriva do esquema do sistema. Qualquer ocorrência do media query em
// JS ou CSS (um "conserto" bem-intencionado que entregaria tema claro para a
// maioria dos celulares corporativos — a pior combinação sob luz de galpão)
// falha o CI.
const NEEDLE = ['prefers', 'color', 'scheme'].join('-') // evita citar o literal aqui

function scan(dir: string, out: string[]) {
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry)
    if (statSync(full).isDirectory()) {
      if (entry !== 'node_modules') scan(full, out)
      continue
    }
    if (!/\.(ts|tsx|css)$/.test(entry)) continue
    if (full.includes('__tests__')) continue
    readFileSync(full, 'utf8')
      .split('\n')
      .forEach((line, i) => {
        if (line.includes(NEEDLE)) out.push(`${full.replace(join(__dirname, '..'), '.')}:${i + 1}`)
      })
  }
}

describe('o tema não segue o esquema do sistema (D-DS-3)', () => {
  it('nenhuma ocorrência do media query em src nem no index.html', () => {
    const out: string[] = []
    scan(join(__dirname, '../src'), out)
    if (readFileSync(join(__dirname, '../index.html'), 'utf8').includes(NEEDLE)) out.push('./index.html')
    expect(out, `esquema do sistema não pode decidir o tema:\n${out.join('\n')}`).toEqual([])
  })
})
