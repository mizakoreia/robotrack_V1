# EXECUCAO — quality-and-accessibility (G0: reconciliação com a realidade)

Onda 10, o gate de release. Escrito DEPOIS das ondas 1–9 já entregues — então a
maioria das INVARIANTES que esta capacidade defende **já vale**, entregue pelas
donas de cada tela. O papel do G0 é separar, tarefa a tarefa: **SATISFEITA** (já
existe e tem prova), **RECONCILIADA** (a invariante vale, mas por mecanismo
diferente do que a tarefa literalmente pede — e mudar agora seria regressão), e
**DELTA** (falta de verdade, e é o que esta onda constrói).

Fonte: varredura de reconciliação (3 leituras paralelas do código em 23/07/2026).

---

## Veredito por grupo

### 1. Fundação de teste

- **1.1 Factories de domínio — RECONCILIADA.** O repo NÃO usa FactoryBot para linhas
  de tenant, de propósito: o `factories_spec` genérico roda toda factory SEM contexto
  de tenant, e sob RLS `workspace_id` nasce nulo → o `NOT NULL`/`WITH CHECK` falha
  (documentado em `spec/factories/audit_logs.rb` e `spec/support/tenancy_helpers.rb`).
  A resolução de `workspace_id` pelo pai que 1.1 exige **já existe** em
  `create_task(robot)` (`tenancy_helpers.rb:41` → `workspace_id: robot.workspace_id`).
  Só `user`/`user_type` (models globais) têm factory. **DELTA menor:** faltam helpers
  `create_project/cell/robot` no idioma de `create_task` (hoje os specs os criam à mão).
- **1.2 `as_member_of` unificado — DELTA (pequeno).** As peças existem separadas:
  `bearer_headers`/`sign_in_as` (`request_auth_helper.rb`) e `make_workspace`/
  `in_workspace`/`add_member` (`tenancy_helpers.rb`), mas NÃO há um helper único que
  abra o contexto RLS junto com a autenticação. Nenhum spec redefine `bearer_for`
  (a dívida que 1.2 cita já não existe). Entregar o combinado é útil.
- **1.3 Guarda de type-check sobre testes do frontend — DELTA.** `tsconfig.json:29`
  EXCLUI os testes; não há script `typecheck`/`tsc --noEmit` sobre eles; a CI só roda
  `backend spec/authorization`. Importar módulo inexistente num teste só quebra em
  runtime do vitest. **É delta real.**

### 2. D14 — strings pt-BR centralizadas

- **2.1 Locales + `default/available_locales` — SATISFEITA (com 1 gap).**
  `config/locales/pt-BR.{notifications,audit,report,…}.yml` existem;
  `application.rb:15` fixa `default_locale = :'pt-BR'`. **DELTA menor:** não há
  `pt-BR.errors.yml` dedicado, e falta `config.i18n.raise_on_missing_translations`
  em test/dev (hoje chave inexistente devolve `translation missing:` string).
- **2.2 `Rt::Message.render` unificado — RECONCILIADA.** Não há renderer único, mas
  `Notifications::MessageBuilder.build` já valida interpolação via `I18n.t` estrito e
  devolve `{msg:, format_version:}`; audit congela `msg` no INSERT. O caminho único
  por-domínio já existe; unificar num `Rt::Message` é refactor cosmético de baixo
  valor sobre código provado.
- **2.3 Colunas `message_key`/`message_args` — RECONCILIADA (conflito de design).** A
  tarefa pede persistir chave+args; o produto DECIDIU o contrário (Decisão 4, D12):
  `notifications`/`audit_logs` **congelam o texto renderizado** (`msg`) + `format_version`,
  com `CHECK` de tamanho no banco. Persistir a chave reabriria a imutabilidade que
  D-IMUT fecha. A invariante que 2.3 quer (banco recusa lixo, tamanho no banco) já vale
  (`msg_max_500`, provado em `notifications/schema_invariants_spec`). **Não implementar.**
- **2.4 i18n frontend tipado — RECONCILIADA.** `src/lib/i18n/*.ts` já centraliza tudo
  em objetos `as const` com membros-função tipados (ex. `advances.conflictBy(author,v)`),
  e um grep-guard de CI reprova literal fora daí. É o mesmo contrato de "quebra o `tsc`
  + fonte única" por outra forma (função tipada em vez de `t(key)` runtime). Migrar para
  `t(key,params)` seria reescrever 28 telas sem ganho de invariante.
- **2.5 Sweeps de literal — RECONCILIADA/DELTA parcial.** Os grep-guards por-domínio já
  existem no frontend; **DELTA:** consolidar num sweep único que pegue também
  concatenação (`"a " + x`) no backend `app/services/{notifications,audit,reports}`.
- **2.6 Verificação do grupo — DELTA (deriva de 2.1/2.5).**

### 3. Contraste medido (a "BREAKING visual") — SATISFEITA (INTEIRA)

- Os três tokens que 3.3 mandaria trocar **já estão nos valores endurecidos** em
  `src/styles/globals.css` (HSL, hex em comentário):
  `--accent-solid #1d4ed8` (6.70:1, não `#3b82f6`), `--danger-solid #b91c1c` (não
  `#ef4444`), tinta N/A `#3f3f46` claro / `#d4d4d8` escuro (não `#a1a1aa`).
- O teste de contraste com composição alfa + tabela de esperados **já existe**
  (`frontend/tests/contrast.test.ts` lendo `src/styles/tokens.json`), mais
  `tokens.test.ts`/`token-source.test.ts`/`no-prefers-color-scheme.test.ts`.
- **NÃO há mudança de cor a fazer.** 3.1/3.2/3.3/3.4 estão satisfeitas por um sistema
  já entregue (design-system, "D-DS-2"), com valores ≥ os alvos da proposta. Reconciliado
  como SATISFEITO — o alerta de "muda o visual" ao usuário não se materializa.

### 4. Teclado e foco — MAJORITARIAMENTE SATISFEITA

- **4.1 `:focus-visible` — DELTA (pequeno).** Não há regra global; o foco é por-componente
  (`Button/Input/IconButton` com `focus-visible:ring-2`). Há `outline-none` SOLTO (sem
  `focus-visible:ring`) em `ProfilePage:21`, `HierarchySearchField:39`, e `UsersPage:292`
  usa `:focus` em vez de `:focus-visible`. **DELTA:** regra `:focus-visible` global +
  corrigir os 3 pontos + sweep anti-regressão.
- **4.2/4.3 Menu/modal — SATISFEITAS.** `PortalMenu` faz Arrow/Home/End, `Escape`→gatilho;
  `Modal` prende foco em ciclo e devolve ao gatilho. `FilterBar` usa `role=tablist/tab` +
  `aria-selected` (ARIA válido; a tarefa pede `aria-pressed`/`aria-checked` — reconciliado,
  ambos comunicam seleção). **DELTA menor:** roving do `PortalMenu` sem `aria-activedescendant`.
- **4.4 E2E de teclado — DELTA (precisa Playwright; ver G6/G7).**

### 5. Leitor de tela, movimento, toque — MAJORITARIAMENTE SATISFEITA

- **5.1 Live-regions do shell — DELTA.** Hoje as regiões vivem por-componente
  (`ConnectionIndicator`, `SaveIndicator`, `NotificationCenter`…), não há
  `#rt-status`/`#rt-notifications`/`#rt-alerts` centralizados e incondicionais no shell.
  **DELTA:** montá-los no `AppShell` + rotear + sweep.
- **5.2 `role=progressbar`/`role=img` — SATISFEITA.** Anéis = `role=img`+`aria-label`
  (com métrica D15), barras = `role=progressbar`+`aria-valuenow`.
- **5.3 Ícone/botão só-ícone/select/pulso — SATISFEITA em grande parte** (sweeps + o
  `successPulse` não move foco). **DELTA menor:** consolidar o sweep de `<button>` só-`svg`.
- **5.4 `prefers-reduced-motion` + luz ambiente parada — SATISFEITA**
  (`globals.css:232`, `ambient.ts` gated; `tests/motion.test.ts`/`ambient.test.ts`).
- **5.5 Auditor de alvo de toque — RECONCILIADA/DELTA parcial.** Convenção ≥32px base /
  ≥40px mobile existe e é testada (`mobileA11y.test.tsx`), mas não há um AUDITOR que meça
  o retângulo efetivo e reprove sobreposição. **DELTA** (precisa layout real → Playwright).
- **5.6 Gate `axe-core` 8 telas × 2 temas — DELTA (precisa Playwright).**

### 6/7. Harness E2E + 5 fluxos — DELTA (o grande)

- Não há `e2e/`, `@playwright/test`, `playwright.config`, nem `rt:seed:e2e` (UUIDs fixos).
- Os 5 fluxos existem como **integração RTL/vitest** (offline, realtime, report, settings)
  — a LÓGICA está coberta; o nível-navegador (service worker real, 2 `BrowserContext`
  autenticados, render A4) não. Três arquivos `*.e2e.test.tsx` são vitest e já anotam
  "o harness Playwright não existe — divergência no EXECUCAO".
- **DELTA:** construir o harness (Chromium disponível neste ambiente; **WebKit e CI são
  handoff** — igual aos demais handoffs de deploy da onda `delivery-and-observability`).

### 8. Orçamentos de performance — PARCIAL

- **8.1 `rt:seed:load` (WS-CARGA/WS-ISCA) — DELTA.** Existe `progress_load_dataset`
  (93k tasks, 1 workspace), mas NÃO no formato WS-CARGA (4/24/240/7440 + advances/people/
  notifications/audit + WS-ISCA com iscas). **DELTA.**
- **8.2 Matcher de variação por 2 tamanhos — DELTA.** Existe `issue_at_most(n).queries`
  (1 tamanho) aplicado a overview/progress (≤2/≤3) e report (≤5). Falta o matcher que meça
  DOIS tamanhos e reprove por variação (a assinatura real de N+1). **DELTA.**
- **8.3 Relatório ≤12 queries constante em 240 robôs — DELTA** (hoje ≤5 em 2.325 tasks).
- **8.4 Orçamento de bundle (gzip/chunk + grafo do entry) — DELTA.** Existe
  `no-heavy-deps.test.ts` (manifesto: recharts/tiptap/slate JÁ removidos), mas **`gsap`
  está presente sem guarda no grafo do entry** e não há teste de tamanho gzip nem scan do
  `stats.json`. **DELTA.**
- **8.5 INP com 24 cards — DELTA (precisa navegador).** Cadência da luz ambiente JÁ testada.
- **8.6 Verificação — DELTA (deriva).**

---

## Ordem de execução (só os DELTAS; o resto é reconciliação)

Agrupados por "fecha sem navegador" (aqui) vs "precisa navegador/CI" (handoff parcial):

**G-A — fecháveis e verificáveis aqui (sem navegador):**
1. i18n: `pt-BR.errors.yml` + `raise_on_missing_translations` em test/dev (2.1).
2. Front type-check: script `typecheck` + incluir testes no `tsc --noEmit`, e a guarda de CI (1.3).
3. Foco: `:focus-visible` global + corrigir `outline-none` solto + sweep (4.1).
4. Bundle: guarda de `gsap` no grafo do entry (estende `no-heavy-deps`) (8.4 parcial).
5. Perf backend: matcher de variação por 2 tamanhos (8.2) + relatório ≤12 sobre dataset
   maior (8.3), com o `rt:seed:load` mínimo necessário (8.1 parcial).
6. Helpers de teste: `as_member_of` + `create_project/cell/robot` (1.2/1.1 delta).
7. Live-regions do shell centralizadas (5.1).

**G-B — precisam navegador (Chromium aqui; WebKit + CI = handoff):**
8. Harness `@playwright/test` + fixtures de 2 contextos + `rt:seed:e2e` UUIDs fixos (6.x).
9. Os 5 fluxos (7.x) e o gate `axe-core` (5.6) e o E2E de teclado (4.4) e o INP (8.5).

**Handoff explícito (nem aqui fecha):** WebKit real, pipeline de CI, retenção de trace —
como os handoffs de `delivery-and-observability` (§5 do VALIDACAO_WSL).

As tarefas RECONCILIADAS/SATISFEITAS são marcadas `[x]` com a nota do porquê; os DELTAS
`[x]` só quando entregues e verdes; o que fica em handoff é anotado como tal (não vira
`[x]` falso).

---

## G6 — Harness E2E CONSTRUÍDO (24/07/2026, campanha de deploy)

A frente escolhida pelo dono. O harness (grupo 6) é o keystone das 14 tarefas
G-B — 4.4/5.5/5.6/7.x/8.5 todas dependem dele. Construído e verificado até onde
o container alcança (sem navegador); a execução em Chromium+WebKit é o handoff WSL,
como os demais handoffs de deploy da onda `delivery-and-observability`.

**Decisão — `@playwright/test` no toolchain do frontend.** O par confirmou que a
adoção da dep é decisão do container. Adotada em `frontend/package.json`
(devDependency) com o harness em `frontend/e2e/` e `frontend/playwright.config.ts`.
Um toolchain node só (não um projeto `e2e/` na raiz com `node_modules` próprio):
o `@playwright/test` divide o mesmo `node_modules` do vitest. Reconcilia o `e2e/`
da raiz que o design cita → `frontend/e2e/`.

**6.1 config — ENTREGUE (browser=handoff).** `playwright.config.ts`: Chromium+WebKit
(sem Firefox, D-QA-1), `retries: 1` só sob CI, trace/vídeo/screenshot só em falha,
`baseURL` de `E2E_BASE_URL` com ABORT se ausente (força o build de produção, não
`vite dev`), `globalTimeout` de 8 min (7.7), `workers` de `PLAYWRIGHT_WORKERS`. A
guarda de service worker (`serviceWorkers()==0` → falha imediata) vive em
`fixtures/session.ts::assertServiceWorkerRegistered`.

**6.2 fixture de 2 contextos + seed determinístico — ENTREGUE + VERIFICADO (seed).**
`fixtures/session.ts`: `apiLogin` (POST `/auth/v1/session` no backend :3000 — o app
chama a porta direto, client.ts) + `authenticatedContext` que injeta a sessão no
`localStorage['robotrack.session']` (o meio que o authStore hidrata) → dois
`BrowserContext` com JWTs distintos (`ownerPage`/`guestPage`). `backend/lib/tasks/
e2e.rake` (`rt:seed:e2e[base]`): UUIDs LITERAIS FIXOS (D-QA-2, sem Faker), owner+guest
com senha conhecida, workspace de id fixo bootstrapado com catálogo de 31. Fonte
única dos ids compartilhada com `fixtures/seed-constants.ts`. **Verificado no
container:** seed idempotente (2×), login de owner+guest autentica, ws owner-ok,
catálogo 31, person do dono. Fora de `app/` de propósito (não eager-load em prod).

**6.3 lint da suíte + smoke — ENTREGUE (smoke=handoff).** `scripts/lint-e2e.mjs`
(reprova `waitForTimeout`/`sleep`/`setTimeout` + >6 interações antes do 1º `expect`)
— **passa** no smoke aqui (`npm run e2e:lint`). `tests/smoke.spec.ts` prova o harness
(build carrega, SW registra, duas sessões distintas) — roda na WSL em Chromium+WebKit.

**Status:** 6.1/6.2/6.3 ficam `[ ]` até o par rodar o smoke verde em Chromium E
WebKit (regra do G0: DELTA vira `[x]` só quando VERDE; o que é handoff é anotado, não
marcado falso). O seed e o lint estão verdes no container; o navegador é o que falta.
`frontend/e2e/README.md` tem o runbook.

**Próximo (após o smoke verde):** os 5 fluxos (7.x) estendem `rt:seed:e2e` com um
cenário por fluxo (`[convite]`/`[offline]`/`[troca]`/`[revogacao]`/`[relatorio]`),
mais 4.4 (E2E teclado), 5.5 (auditor de toque), 5.6 (axe-core), 8.5 (INP).

### G6 — correções do smoke em navegador real (par WSL)

O par rodou o smoke: Chromium 2/2, WebKit 1/2. A única falha era do HARNESS, não
do produto.

- **BUG 14 — `context.serviceWorkers()` é Chromium-only.** Devolve lista vazia no
  WebKit mesmo com o SW registrado e ativo (o par mediu: `navigator.serviceWorker.
  ready` resolve `/sw.js` nos dois). `assertServiceWorkerRegistered` passou a
  afirmar pela PÁGINA (`navigator.serviceWorker.ready`), cross-browser, e recebe
  `page` em vez do contexto. Mensagem de erro corrigida (a antiga mandava caçar a
  topologia, que estava certa).
- **Guarda de banco no seed.** O par rodou `rt:seed:e2e` contra `robotrack_dev` (era
  o que estava no ar) e plantou os usuários E2E junto da demo. `E2eSeed.guard_database!`
  agora RECUSA banco cujo nome não contenha `e2e`/`test` (ou `E2E_SEED_FORCE=1`), e
  nunca roda em produção. Verificado: bloqueia `robotrack_dev`, libera `robotrack_test`.

**Decisões operacionais (do par, registradas):** serviço = `vite preview` + backend
:3000 (sem CORS, sem nginx); banco = `robotrack_e2e` dedicado, recriado por rodada
(idempotência resolve re-execução, não contaminação entre rodadas de convite/
revogação). Ambas no `frontend/e2e/README.md`.

Após o par re-rodar Chromium+WebKit verdes, 6.1/6.2/6.3 fecham e seguem os 5 fluxos.

### G6 FECHADO + regra de contraste de campo (24/07/2026)

**Smoke verde nos DOIS navegadores** (par WSL): 4/4 Chromium+WebKit. 6.1/6.2/6.3
→ `[x]`. Observação do par para os fluxos: o WebKit registra o SW mais devagar
(~10.7s vs 5.9s) — se um fluxo ficar flaky SÓ no WebKit, a suspeita começa por
timing de service worker, não pelo cenário.

**Restrição de topologia registrada:** demo e E2E não coexistem hoje (o bundle
embute a origem da API em build time; `E2E_API_URL` só afeta o login da fixture). O
backend da :3000 tem de apontar pro `robotrack_e2e` na rodada (troca manual). O
caminho para CI determinístico (VITE_API_URL + backend dedicado) está no
`frontend/e2e/README.md` como follow-up do operador.

**Regra F de contraste (convention-sweep) — fecha a CLASSE do bug branco-sobre-branco.**
O contraste ilegível bateu DUAS vezes (login, depois criar-robô): campo nativo sem
token de fundo cai no branco do navegador e some no tema escuro. Em vez de caçar
campo a campo, `tests/convention-sweep.test.ts` ganhou a regra F: todo
`<input>/<select>/<textarea>` nativo precisa de fundo temático (inline `bg-*`, classe
de campo `.input`/`.input-base`/`.surface-*`, ou className computada). Extrator de tag
que respeita `=>` e `{}` + neutralização de comentários (senão `<input>` citado em
comentário vira falso positivo). PROVADO que morde: flaga o padrão do login velho
(estático sem bg) e o do robô velho (sem className); passa nos temáticos. Suíte
frontend 543/0 (95 arquivos), incluindo a regra F verde no código atual.

**vitest.config:** exclui `e2e/**` da coleta — os specs de Playwright rodam sob
`@playwright/test`, não vitest (senão o `npm test`/CI falha no import). Os testes de
INTEGRAÇÃO `*.e2e.test.tsx` em `src/` seguem vitest, intocados.

### Fluxo 1 (convite) — slice 1 (núcleo do plumbing)

7.1 é grande e browser-gated; construído em slices. **Slice 1 entregue:**
- `rt:seed:e2e[convite]`: base + hierarquia mínima (projeto→célula→robô→1 tarefa a
  40%, ids fixos) para o convidado registrar +10 depois. VERIFICADO no container
  (idempotente 2×; `unique_by: :id` no insert_all por causa do índice de position
  DEFERRABLE). Constantes espelhadas em `fixtures/seed-constants.ts`.
- `e2e/tests/invite.spec.ts` (slice 1): dono cria convite `edit` pela UI, pega o
  link, o convidado (já autenticado) abre → aceite automático → o membro aparece no
  painel do dono (asserção web-first, sem reload manual — testa o realtime da lista
  de membros). Navega pelo CAMINHO do link (não a URL absoluta) para desacoplar de
  APP_URL. e2e-lint verde (≤6 interações antes do 1º expect).

**Próximas slices de 7.1 (depois do núcleo verde no par):** convidado troca para o
workspace do dono e registra +10 (40→50); convite `view` com controle desabilitado +
PATCH forjado → 403; sobrevivência do token ao redirect do Google (precisa de stub de
OAuth — candidato a ficar como integração, não E2E). 7.1 fica `[ ]` até tudo verde.

**Achado a confirmar no par:** ao aceitar um convite, o BUG-13-fix auto-seleciona o
workspace PRÓPRIO (role owner) — então o convidado cai no workspace dele, não no que
acabou de entrar. Provável ajuste de UX (aceite → abrir o workspace convidado), a
decidir quando a slice 2 rodar.

### BUG 15 — a fixture nunca autenticava (e o smoke passava por acaso)

O par rodou o invite.spec e caiu na TELA DE LOGIN nos dois navegadores. Causa:
`fixtures/session.ts` fazia `as { data: Session }` (Session = camelCase `accessToken`),
mas a API devolve `data.access_token` (snake_case). `as` é cast de TIPO, não
mapeamento em runtime → `accessToken` undefined → `JSON.stringify` descarta a chave →
o contexto nasce SEM token → cai no login. Consertado: MAPEIA
`access_token → accessToken`.

**E o smoke 4/4 era falso positivo** (mesma família do falso positivo do staging): as
duas asserções passavam na tela de login (`#root` visível lá também; o `user` era
serializado, só o token sumia). O 6.3 ("entra AUTENTICADA sem clicar no login") nunca
foi provado. `smoke.spec` endurecido: afirma (a) `accessToken` no localStorage, (b) o
destino "Visão Geral" da sidebar (só existe no shell autenticado), (c) ausência do
heading "Entrar".

**CORS :4173** (achado do par): o default do `cors.rb` era `:5173,:3000` — o preview
:4173 (alvo obrigatório do E2E) ficava fora, o preflight voltava sem
`access-control-allow-origin` e nenhuma chamada passava (WorkspaceContext degradava
para "Recarregar"). Default passou a incluir `:4173`; procedimento no `e2e/README.md`.

**As 4 correções de UI (sino, dashboard→/, card clicável, slider do modal) o par
CONFIRMOU no app vivo** (Chromium real). Só o harness estava quebrado, não o produto.

### Fluxo 1 slice 2 + o E2E rodando NO CONTAINER (Chromium)

**Descoberta que destravou a frente:** a WSL só é necessária para **Docker e
WebKit**. Chromium está pré-instalado aqui, então o loop E2E inteiro (build de
produção + `vite preview` + backend contra `robotrack_e2e` + Playwright) roda no
container. Único ajuste: `E2E_CHROMIUM_PATH` no `playwright.config.ts`, porque a
revisão gerenciada em `PLAYWRIGHT_BROWSERS_PATH` não é a que esta versão baixaria
(sem a variável, o comportamento é o padrão — WSL/CI intocados).

**Slice 1 (convite) VALIDADA aqui**, em Chromium: os consertos de locator ambíguo
(região `Equipe` + diálogo) e o atalho da topbar estão verdes sem depender do par.

**Slice 2 ENTREGUE** (`e2e/tests/advance.spec.ts`): o membro `edit` leva a tarefa de
40% a 50% pela UI nova (arrasta o slider, **solta** → a observação abre com o valor
solto), comenta, registra, e o valor **sobrevive ao reload** (é servidor, não estado
de tela). O reload mora no MESMO teste de propósito: um teste separado dependeria da
ordem de execução para o avanço existir, e ordem entre testes é acoplamento.

**Uma semente para a suíte inteira.** `rt:seed:e2e[convite]` passou a semear TRÊS
usuários: `owner` (convida), `guest` **não-membro** (é quem o spec do convite
convida) e `member` (já `edit`, é quem o spec do avanço usa). Com um usuário só, um
dos dois specs teria de rodar contra outro estado de banco — ou depender da ordem.
`[avanco]` fica como alias. Fixture ganhou `memberPage` e o helper
`entrarNoWorkspace` (quem é membro do workspace de OUTRO precisa chegar com ele
selecionado — a primeira carga escolhe o PRÓPRIO, fix do BUG 13).

**Armadilha registrada:** com um backend conectado, `DROP DATABASE` falha em
SILÊNCIO e a rodada seguinte parte do estado antigo — o teste reprova por um motivo
que não é o dele. Termine as conexões (`pg_terminate_backend`) antes. Está no
`frontend/e2e/README.md`.

**Estado:** suíte E2E **4/4 em Chromium** (smoke 2 + convite 1 + avanço 1), em
paralelo, contra banco recriado. **7.1 segue `[ ]`**: faltam o convite `view` com
controle desabilitado + `PATCH` forjado 403, e o token no redirect do Google; e o
WebKit é confirmação do par.

---

## G-B1 — a11y de navegador: teclado (4.4) + auditor de toque (5.5) + axe (5.6)

Sessão de fechamento (25/07/2026) no **Mac do dono**, NÃO no container Linux das
notas antigas. Prova empírica do ambiente: sem `/opt/pw-browsers` (nenhum navegador
Playwright), ruby 2.6 do sistema (Rails 8 precisa de 3.2), e a **demo viva** em
`:5173`/`:3000` (o dono testando no celular). Consequência: repontar o backend
`:3000` para `robotrack_e2e` — o único jeito de rodar E2E aqui (README §88-90) —
**derrubaria a demo**. Logo, a EXECUÇÃO em navegador destes três gates é HANDOFF
documentado (§6d do `VALIDACAO_WSL.md`), mesma classe de WebKit/CI. O que fecha
aqui: spec escrito + `e2e:lint` verde + `tsc` limpo + a devDep instalada — o
precedente da casa (`invite-by-code` G5.2, `join-workspace-by-code` G2.1).

- **4.4 E2E de teclado — ENTREGUE (execução=handoff).** `e2e/tests/keyboard.spec.ts`:
  percurso Visão Geral → Projeto → Célula → Robô → (modal de avanço) → Minhas
  Tarefas → Relatório SÓ com Tab/setas/Enter/Escape. Cards por Enter (`EntityCard`
  `role=button`), modal aberto por `ArrowRight`+keyup (a UX nova abre a observação no
  fim do "arraste"), `Escape` devolve o foco ao slider (contrato 4.3), avanço 40→50
  completado por teclado. Helper `tabPara(nome)` varre por nome acessível — NÃO fixa
  contagem de Tab (a ordem é detalhe de layout; os locators se afinam na 1ª execução
  no par, como as slices 1-2).
- **5.5 Auditor de toque — ENTREGUE (execução=handoff).** `e2e/a11y/touch-targets.ts`
  mede o retângulo EFETIVO no contexto da página: base (`getBoundingClientRect`) unida
  ao pseudo `::before`/`::after` absoluto com inset negativo (o padrão de ampliar o
  toque sem inchar layout). Reprova < 32px (requisito de ambiente, > 24px de WCAG
  2.5.8) e sobreposição entre áreas ESTENDIDAS adjacentes; ISENTA link de texto inline
  em fluxo. `touch-targets.spec.ts` roda em 4 telas mobile (375×812) + prova de
  não-vacuidade (planta 20px, afirma que é pego).
- **5.6 Gate axe-core — ENTREGUE (execução=handoff).** `@axe-core/playwright@^4.12.1`
  instalada. `e2e/a11y/axe.ts` roda o axe (WCAG 2.0/2.1 A/AA) e conta os `incomplete`
  de CONTRASTE como não-aprovação — o resto de `incomplete` (julgamento humano) fica
  de fora, senão o gate vira ruído e é desligado. `setTheme` alterna `.light`. Spec:
  8 telas × 2 temas + Robô com o modal aberto (claro) + prova de não-vacuidade
  (`<button>` sem nome → `button-name` crítico).

**Decisão de execução DE-QA-B1.** Os três specs referenciam o SEED `[convite]` já
existente (ids fixos) — nenhum seed novo. O erro de `tsc` que aparece em
`e2e/fixtures/session.ts:61` (`base.request`) é PRÉ-EXISTENTE e cosmético do
type-check ad-hoc: o arquivo rodou verde 4/4 no container sob o esbuild do Playwright
(que não faz `tsc` estrito). Não tocado — corrigir um arquivo provado por um
type-check que o runtime não usa seria regressão de risco.

**Gates verdes aqui:** `npm run lint` (100%), `npm run e2e:lint` (8 specs),
`typecheck:test-imports`, `tsc` sobre `e2e/**` (só o pré-existente de session.ts).

---

## G-B2 — fluxos E2E: 7.1 (completo) + 7.2 (offline) + 7.3 (drenagem)

Continuação dos 5 fluxos. Todos os specs escritos + `e2e:lint` verde + `tsc`
limpo; execução em navegador é HANDOFF (§6e do `VALIDACAO_WSL.md`), pelo mesmo
motivo do G-B1 (Mac do dono, demo viva). Nenhum seed NOVO — reusam `[convite]`.

- **7.1 — FECHADO em slices.** Slices 1-2 já eram verdes em Chromium no container
  (`invite.spec.ts`/`advance.spec.ts`). **Slice 3** (`invite-view.spec.ts`): o membro
  `view` não tem o slider no DOM (fora do DOM, não `disabled`) + POST de avanço
  forjado com o token do view → **403** (não 404: é membro, a falha é de PAPEL). A
  **slice 4** (token no redirect do Google) é `test.fixme`: CANDIDATO A INTEGRAÇÃO
  (§274) — stub de OAuth, coberto no `/auth/callback` em RTL.
- **7.2 — ENTREGUE.** `offline-advance.spec.ts`: `context().setOffline(true)` (rede
  REAL desligada), avanço 40→50 enfileira, overlay mostra 50, indicador "Alterações
  pendentes" e `Salvo` (exact) COUNT 0. A invariante de estado honesto do PRODUCT.md.
- **7.3 — ENTREGUE.** `offline-drain.spec.ts`: 3 avanços offline, `reload` ainda
  offline (overlay derivado da fila sobrevive ao remount), reconexão → dreno →
  "Salvo"; `expect.poll` no `GET /tasks/:id/advances` converge em 3 e cada
  `recorded_at` < o carimbo de reconexão. Sub-caso robô-offline = `test.fixme`
  (seam aberto de `offline-pwa`: o `BatchRobotWizard` não tem produtor de fila).

**Decisão de execução DE-QA-B2.** Semeamos um quarto usuário `viewer` (membro
`view`, id …004), espelho do `member` (edit): o slice-view precisa de um membro view
pré-existente, e re-convidar `guest` (consumido como convidado `edit` pela slice 1)
colidiria no banco único de uma rodada. Fixture ganhou `viewerContext`/`viewerPage`;
`apiBase(baseURL)` foi exportado para o spec forjar o POST no backend :3000.

**Gates:** `e2e:lint` (11 specs), `tsc` sobre `e2e/**` (só o pré-existente de
session.ts:61 `base.request`, cosmético), `ruby -c` do `e2e.rake` OK.
