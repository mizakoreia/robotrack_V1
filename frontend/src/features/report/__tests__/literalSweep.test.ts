import { describe, expect, it } from 'vitest'
import { readFileSync, readdirSync } from 'node:fs'
import { join } from 'node:path'

// commissioning-report 8.2 (D14/D-R9/§5.1) — os sweeps do lado do cliente.
//
// 1. LITERAIS: nenhum texto pt-BR fixo no código de apresentação do documento
//    (`features/report/`, fora de testes) — todo texto do documento viaja no
//    payload (`labels`/`footer`/`signatures`), resolvido no servidor. O sweep
//    remove comentários (que são pt-BR de propósito) e reprova qualquer literal
//    de string com caractere acentuado, apontando arquivo e linha.
//
// 2. GLIFOS: nenhum caractere ≥ U+2500 fora de {✓ ◐ ○} no código da feature —
//    o glifo NUNCA é digitado em JSX (vem do payload); emoji introduzido depois
//    falha aqui nomeando o caractere.

const FEATURE_DIR = join(__dirname, '..')
const SOURCES = readdirSync(FEATURE_DIR)
  .filter((f) => /\.(ts|tsx)$/.test(f))
  .map((f) => join(FEATURE_DIR, f))

function stripComments(src: string): string {
  return src.replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/[^\n]*/g, '')
}

describe('sweep de literais e glifos em features/report/ (8.2)', () => {
  it('há fontes para varrer', () => {
    expect(SOURCES.length).toBeGreaterThan(5)
  })

  it('nenhum literal pt-BR (acentuado) fora de comentários', () => {
    const offenders: string[] = []
    for (const file of SOURCES) {
      const code = stripComments(readFileSync(file, 'utf8'))
      code.split('\n').forEach((line, i) => {
        const literals = line.match(/'[^']*'|"[^"]*"|`[^`]*`/g) ?? []
        for (const lit of literals) {
          if (/[À-ÖØ-öø-ÿ]/.test(lit)) offenders.push(`${file.split('/').pop()}:${i + 1} → ${lit}`)
        }
      })
    }
    expect(offenders).toEqual([])
  })

  it('nenhum caractere fora de {✓ ◐ ○} + texto básico no código da feature', () => {
    const offenders: string[] = []
    const allowed = new Set(['✓', '◐', '○'])
    for (const file of SOURCES) {
      const code = stripComments(readFileSync(file, 'utf8'))
      for (const ch of code) {
        if (ch.codePointAt(0)! >= 0x2500 && !allowed.has(ch)) {
          offenders.push(`${file.split('/').pop()} → U+${ch.codePointAt(0)!.toString(16)} (${ch})`)
        }
      }
    }
    expect(offenders).toEqual([])
  })
})
