import { describe, it, expect } from 'vitest'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'

// delivery-and-observability 3.3 — conformidade do contrato de cache do bundle no
// nginx. É a versão testável-aqui do smoke de headers (o smoke real, contra o CDN
// publicado, é HANDOFF de deploy). Uma regressão por clique no console do provedor
// não é pega aqui, mas uma regressão no nginx.conf versionado é.
const NGINX = readFileSync(resolve(__dirname, '../../../../nginx.conf'), 'utf8')

// Extrai o corpo de um bloco `location <matcher> { ... }`.
function locationBlock(matcher: string): string {
  // Espaço antes da `{` para `location /` não casar `location /api/`.
  const idx = NGINX.indexOf(`location ${matcher} {`)
  if (idx === -1) return ''
  const open = NGINX.indexOf('{', idx)
  let depth = 0
  for (let i = open; i < NGINX.length; i++) {
    if (NGINX[i] === '{') depth++
    if (NGINX[i] === '}') {
      depth--
      if (depth === 0) return NGINX.slice(open, i)
    }
  }
  return ''
}

describe('contrato de cache do PWA (3.3)', () => {
  it('sw.js → no-store (o service worker sempre revalida)', () => {
    expect(locationBlock('= /sw.js')).toMatch(/Cache-Control\s+"no-store/)
  })

  it('index.html → no-store (o shell sempre revalida)', () => {
    expect(locationBlock('= /index.html')).toMatch(/Cache-Control\s+"no-store/)
  })

  it('/assets/ → immutable, 1 ano (hash muda a URL a cada build)', () => {
    const block = locationBlock('/assets/')
    expect(block).toMatch(/immutable/)
    expect(block).toMatch(/max-age=31536000/)
  })

  it('/api/ → no-store (nunca cachear resposta autenticada)', () => {
    expect(locationBlock('/api/')).toMatch(/Cache-Control\s+"no-store/)
  })

  it('SPA fallback: qualquer rota cai no index.html', () => {
    expect(locationBlock('/')).toMatch(/try_files.*index\.html/)
  })
})
