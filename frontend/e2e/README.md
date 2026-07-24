# Harness E2E (quality-and-accessibility, grupo 6)

Playwright — Chromium + WebKit — contra o **build de produção servido** (nunca
`vite dev`: o service worker de D7 só registra em produção). O estado inicial vem
sempre do backend (`rt:seed:e2e[cenario]`, UUIDs fixos), nunca da UI.

## Estrutura

- `../playwright.config.ts` — config (Chromium+WebKit, retry só sob CI, trace/vídeo
  só em falha, `baseURL` de `E2E_BASE_URL`).
- `fixtures/seed-constants.ts` — os ids/credenciais FIXOS, espelho do
  `backend/lib/tasks/e2e.rake` (fonte única compartilhada seed↔spec).
- `fixtures/session.ts` — login pela API + fixture de **dois** `BrowserContext`
  autenticados (`ownerPage`/`guestPage`) + guarda de service worker (6.1).
- `scripts/lint-e2e.mjs` — reprova `waitForTimeout`/`sleep`/`setTimeout` e >6
  interações antes do 1º `expect` (6.3). Roda com `npm run e2e:lint`.
- `tests/smoke.spec.ts` — smoke do harness (build carrega, SW registra, duas
  sessões distintas).

## Como rodar (na WSL, com Docker + navegador)

```bash
# 1. instalar o Playwright (uma vez) — Chromium já está na WSL; WebKit é download.
cd frontend && npm install && npx playwright install chromium webkit

# 2. servir o BUILD DE PRODUÇÃO + backend (ex.: via a stack de staging, ou:)
npm run build && npx vite preview --port 4173 &   # front prod em :4173
#    backend em :3000 (o app chama a :3000 direto — client.ts força a porta)

# 3. semear o estado E2E determinístico
cd ../backend && bundle exec rails 'rt:seed:e2e[base]'

# 4. rodar
cd ../frontend
E2E_BASE_URL=http://localhost:4173 npm run e2e
#    E2E_API_URL sobrepõe a origem do backend se não for :3000 do mesmo host.
```

## Verificado no container (sem navegador)

- `rt:seed:e2e[base]` roda idempotente (2×), cria owner+guest com senha conhecida,
  workspace de id fixo + catálogo de 31, e o login de ambos autentica.
- `npm run e2e:lint` passa no smoke.

## Handoff (WSL) — o que só o navegador fecha

- Rodar `smoke.spec.ts` verde em **Chromium E WebKit**.
- Confirmar a **topologia de serviço** do E2E: o app chama o backend na `:3000`
  direto (não pela proxy `/api` do nginx). Contra a stack de staging, isso exige
  CORS liberado para a origem do front — vale confirmar como servir os dois no
  mesmo teste (nginx servindo o bundle + backend em :3000, ou `vite preview`).
- Se o banco E2E for persistente entre rodadas, o seed é idempotente; se for
  recriado por rodada, `rt:seed:e2e` roda do zero.
