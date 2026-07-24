#!/usr/bin/env node
// quality-and-accessibility 6.3 — lint da suíte E2E. Reprova os dois vícios que
// tornam um E2E frágil e ilegível:
//   (a) espera por TEMPO (`waitForTimeout`/`sleep`/`setTimeout`) — flake garantido;
//       a espera certa é por ESTADO (`expect(...).toBeVisible()` etc.).
//   (b) mais de 6 interações de UI antes do primeiro `expect` — teste que "faz" um
//       roteiro inteiro antes de afirmar nada esconde ONDE quebrou; o seed (D-QA-2)
//       existe justamente para o teste não precisar clicar pra montar estado.
// Espelha o padrão dos guardas do repo (scripts/check-test-imports.mjs).
import { readdirSync, readFileSync, statSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const E2E_DIR = join(dirname(fileURLToPath(import.meta.url)), '..', 'tests')
const INTERACTIONS = /\.(click|fill|press|check|uncheck|selectOption|hover|tap|type|dblclick|setChecked|dragTo)\s*\(/g
const TIME_WAITS = /\b(waitForTimeout|setTimeout)\s*\(|\bsleep\s*\(/

function walk(dir) {
  const out = []
  for (const name of readdirSync(dir)) {
    const p = join(dir, name)
    if (statSync(p).isDirectory()) out.push(...walk(p))
    else if (/\.spec\.ts$/.test(name)) out.push(p)
  }
  return out
}

const violations = []
let files
try {
  files = walk(E2E_DIR)
} catch {
  console.log('[e2e-lint] sem specs em e2e/tests ainda — nada a checar.')
  process.exit(0)
}

for (const file of files) {
  const src = readFileSync(file, 'utf8')

  src.split('\n').forEach((line, i) => {
    if (TIME_WAITS.test(line)) {
      violations.push(`${file}:${i + 1} — espera por TEMPO (${line.trim()}); espere por ESTADO.`)
    }
  })

  // Conta interações antes do 1º `expect(` por bloco de teste (heurística por
  // arquivo: a 1ª ocorrência de `expect(` fecha a contagem).
  const firstExpect = src.indexOf('expect(')
  const head = firstExpect === -1 ? src : src.slice(0, firstExpect)
  const interactions = (head.match(INTERACTIONS) || []).length
  if (interactions > 6) {
    violations.push(
      `${file} — ${interactions} interações de UI antes do 1º expect (máx 6). ` +
        'Semeie o estado com rt:seed:e2e em vez de clicar até lá (D-QA-2).',
    )
  }
}

if (violations.length) {
  console.error('[e2e-lint] REPROVADO:\n' + violations.map((v) => '  ' + v).join('\n'))
  process.exit(1)
}
console.log(`[e2e-lint] OK — ${files.length} spec(s) sem espera-por-tempo nem excesso de interação.`)
