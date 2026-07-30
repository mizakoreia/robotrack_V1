import { describe, it, expect } from 'vitest'
import { readFileSync, readdirSync, statSync } from 'node:fs'
import { join, resolve } from 'node:path'
import { feedbackText } from '../feedback'

// send-feedback / D14 — nenhum literal de texto de feedback fora do módulo único.
// Mesma guarda de `invitations.i18n.test.ts`: um arquivo que repita uma frase ao
// pé da letra (em vez de importar a chave) é infrator.

const SRC = resolve(__dirname, '../../..')
const MODULO = resolve(SRC, 'lib/i18n/feedback.ts')

function arquivosDeCodigo(dir: string, encontrados: string[] = []): string[] {
  for (const entrada of readdirSync(dir)) {
    const caminho = join(dir, entrada)
    if (statSync(caminho).isDirectory()) {
      if (entrada === 'node_modules') continue
      arquivosDeCodigo(caminho, encontrados)
    } else if (/\.(ts|tsx)$/.test(entrada)) {
      encontrados.push(caminho)
    }
  }
  return encontrados
}

const FRASES = Object.values(feedbackText)
  .filter((valor): valor is string => typeof valor === 'string')
  .filter((frase) => frase.length >= 30)

describe('textos de feedback vivem num módulo único (D14)', () => {
  it('há frases suficientes para a varredura não ser vácua', () => {
    expect(FRASES.length).toBeGreaterThan(5)
  })

  it('nenhum arquivo fora do módulo repete uma dessas frases', () => {
    const infratores: string[] = []

    for (const arquivo of arquivosDeCodigo(SRC)) {
      if (arquivo === MODULO) continue
      if (arquivo.includes('__tests__')) continue

      const conteudo = readFileSync(arquivo, 'utf8')
      for (const frase of FRASES) {
        if (conteudo.includes(frase)) {
          infratores.push(`${arquivo.replace(SRC, 'src')} → "${frase.slice(0, 40)}…"`)
        }
      }
    }

    expect(infratores).toEqual([])
  })

  it('as telas de feedback importam do módulo em vez de escrever texto', () => {
    const telas = [
      resolve(SRC, 'features/feedback/SendFeedbackDialog.tsx'),
      resolve(SRC, 'features/feedback/FeedbackInbox.tsx'),
    ]
    for (const tela of telas) {
      expect(readFileSync(tela, 'utf8')).toMatch(/from ['"].*i18n\/feedback['"]/)
    }
  })
})
