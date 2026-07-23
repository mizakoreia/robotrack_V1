// quality-and-accessibility 1.3 — guarda de import em testes.
// O tsconfig do build EXCLUI os testes, então um teste importando módulo
// inexistente (`../pages/CheckoutPage`) só quebra em runtime do vitest, dentro de
// um `describe` que alguém pode marcar `skip`. Esta guarda roda o `tsc` sobre os
// testes e REPROVA em TS2307 (module-not-found) — o defeito que 1.3 defende.
// (O type-check estrito COMPLETO dos corpos de teste é dívida à parte: 122 erros
// pré-existentes de harness — mocks, lib es2022, @types/node — fora deste guarda.)
import { execSync } from 'node:child_process'

let out = ''
try {
  out = execSync('npx tsc --noEmit -p tsconfig.test.json', { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] })
} catch (e) {
  out = `${e.stdout || ''}${e.stderr || ''}`
}
const notFound = out.split('\n').filter((l) => /error TS2307/.test(l))
if (notFound.length) {
  console.error(`[check-test-imports] ${notFound.length} import(s) inexistente(s) em teste:`)
  for (const l of notFound) console.error('  ' + l.trim())
  process.exit(1)
}
console.log('[check-test-imports] OK — nenhum import inexistente em teste.')
