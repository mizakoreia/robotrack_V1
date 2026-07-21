import { describe, it, expect } from 'vitest'
import { readFileSync, readdirSync, statSync } from 'node:fs'
import { join, resolve } from 'node:path'
import { inviteText } from '../invitations'

// workspace-invitations 6.4 / D14 — nenhum literal de mensagem de convite fora
// do módulo único.
//
// Não é purismo de i18n. São as mensagens que o usuário lê no pior momento
// (convite errado, acesso perdido) e que precisam contar a MESMA história em
// todas as telas. Uma frase duplicada num componente sobrevive à revisão, some
// do radar e envelhece: seis meses depois a tela diz "peça um novo convite" e o
// toast diz "convite inválido", para o mesmo erro.
//
// A varredura pega qualquer arquivo de código que repita, ao pé da letra, uma
// frase do módulo — inclusive quando alguém copiar o texto em vez de importar a
// chave.

const SRC = resolve(__dirname, '../../..')
const MODULO = resolve(SRC, 'lib/i18n/invitations.ts')

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

// Só as mensagens ESTÁTICAS e longas o bastante para serem inequívocas: rótulos
// curtos ("Fechar", "Remover") e validações genéricas de campo ("Informe um
// e-mail válido.", que a tela de login já usava desde a Onda 2) são vocabulário
// comum de UI — duplicá-los não é o problema que esta guarda existe para pegar.
const FRASES = Object.values(inviteText)
  .filter((valor): valor is string => typeof valor === 'string')
  .filter((frase) => frase.length >= 30)

describe('mensagens de convite vivem num módulo único (6.4)', () => {
  it('há frases suficientes para a varredura não ser vácua', () => {
    expect(FRASES.length).toBeGreaterThan(10)
  })

  it('nenhum arquivo fora do módulo repete uma dessas frases', () => {
    const infratores: string[] = []

    for (const arquivo of arquivosDeCodigo(SRC)) {
      if (arquivo === MODULO) continue
      // O próprio teste cita frases ao verificar comportamento.
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

  it('as telas de convite importam do módulo em vez de escrever texto', () => {
    const telas = [
      resolve(SRC, 'features/auth/InviteRoute.tsx'),
      resolve(SRC, 'features/team/TeamPanel.tsx'),
      resolve(SRC, 'features/team/InviteDialog.tsx'),
      resolve(SRC, 'lib/auth/session.ts'),
      resolve(SRC, 'lib/workspace/accessRevoked.ts'),
    ]

    for (const tela of telas) {
      expect(readFileSync(tela, 'utf8')).toMatch(/from ['"].*i18n\/invitations['"]/)
    }
  })
})
