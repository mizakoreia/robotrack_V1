import { describe, expect, it } from 'vitest'
import { readFileSync } from 'node:fs'
import { join } from 'node:path'

// design-system 8.3 (D-DS-7) — guarda que impede a dívida de VOLTAR. Recharts,
// TipTap e Slate foram desinstalados (a única entrada de texto livre do produto é
// o comentário de avanço, um `<textarea>` < 100 chars — §2.4). Também barra
// `@radix-ui/*` e `class-variance-authority` (os primitivos são feitos à mão, sem
// Radix e sem CVA, seguindo Button.tsx/Card.tsx). Um `pnpm add recharts`
// distraído falha o CI nomeando o pacote.
const pkg = JSON.parse(readFileSync(join(__dirname, '../package.json'), 'utf8')) as {
  dependencies?: Record<string, string>
  devDependencies?: Record<string, string>
}

const FORBIDDEN = [/^recharts$/, /^@tiptap\//, /^slate($|-)/, /^@radix-ui\//, /^class-variance-authority$/]

describe('a dívida do template não volta (D-DS-7)', () => {
  it('nenhuma dependência proibida no manifesto', () => {
    const all = Object.keys({ ...pkg.dependencies, ...pkg.devDependencies })
    const offenders = all.filter((name) => FORBIDDEN.some((re) => re.test(name)))
    expect(offenders, `dependências proibidas de volta (Recharts/TipTap/Slate/Radix/CVA):\n${offenders.join('\n')}`).toEqual([])
  })
})
