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

## Topologia confirmada (validada na WSL)

- **Serviço:** `vite preview` (bundle prod em :4173) + backend solto na `:3000`.
  O app chama a `:3000` direto (`client.ts` força a porta), então `E2E_API_URL`
  NÃO é preciso — o default derivado (`u.port = '3000'`) acerta e não há preflight
  CORS bloqueado. Preferido ao nginx (que exigiria `upstream backend` resolvível e
  amarraria o E2E ao build da imagem de ~15 min).
- **Banco:** DEDICADO (`robotrack_e2e`), **recriado por rodada**. A idempotência do
  seed resolve RE-EXECUÇÃO, não CONTAMINAÇÃO: convite/revogação MUTAM estado, então
  rodadas não podem partilhar banco. O `rt:seed:e2e` RECUSA rodar contra um banco
  cujo nome não contenha `e2e`/`test` (guarda contra cair no `robotrack_dev`).

## Handoff (WSL) — o que só o navegador fecha

- Rodar `smoke.spec.ts` verde em **Chromium E WebKit** (Chromium 149 + WebKit 26.5
  já instalados na WSL).
- O service worker é afirmado por `navigator.serviceWorker.ready` (cross-browser),
  NÃO por `context.serviceWorkers()` (Chromium-only — BUG 14).
