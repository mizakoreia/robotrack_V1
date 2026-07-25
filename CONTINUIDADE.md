# Continuidade — estado em 25/07/2026 (`quality-and-accessibility` FECHADA 39/39 → **25/25 changes** do núcleo + 4 changes novas publicadas; execução E2E em handoff)

Ponto de retomada do porte. Para uma sessão nova de agente, o prompt de partida
está em [PROMPT DE RETOMADA](#prompt-de-retomada), no fim.

## Onde está o trabalho (modelo de git ATUAL)

**Mudou desde as ondas iniciais: não é mais empilhamento de branches.** Agora:

- Todo o trabalho vive em `main` — **`main` é a versão mais atual** (tip `6625be6`,
  após a campanha de deploy + a rodada de UI/UX + as slices 1-2 do Fluxo 1 E2E + as
  changes `invite-by-code`, `join-workspace-by-code`, `code-only-invites` e
  `owner-only-card-delete`, mais os fixes de UI da demo — responsividade mobile
  (`705a0c2`), swipe-to-reveal no repouso (`cd9722d`), remoção da luz ambiente
  (`bac3535`) e a lixeira dos cards no desktop (`6625be6`) — ver as seções abaixo).
- **Rodada `impeccable-remediation` (change nova, EM ANDAMENTO grupo a grupo).**
  Formaliza a `CRITICA_IMPECCABLE.md` (69 achados) como UMA change OpenSpec com 6
  grupos ordenados por dor do operador (mapa em `openspec/changes/impeccable-remediation/`).
  Marcador de segurança: `git tag pre-impeccable-remediation` @ `c2532a8` (voltar:
  `git reset --hard pre-impeccable-remediation`). **G0** (`017e8b0`), **G1**
  (contraste + alvo de toque) e **G2** (harden modais/navegação) FECHADOS e no `main`;
  **G3–G6 aguardam OK do dono entre grupos**. G1: slider/StatusSelect com alvo de luva
  (≥32/40px), Button/login/sino/IconButton em tokens AA (submit do login 3,68:1→6,70:1
  medido), gate `tests/touch-and-contrast-usage.test.ts`. G2: AdvanceModal virou modal
  de verdade (primitivo `Modal`: portal/trap/scroll-lock/max-h/× de toque), gaveta
  mobile com trap/Esc/`inert`, classes CSS mortas corrigidas (`.page-title`/`.input-base`/
  `text-text`), `color-scheme` declarado, `PortalMenu` focável, `Tooltip` acessível,
  sinal honesto de offline no avanço; teste novo `harden-g2.test.tsx`. Arquivos de túnel
  (`vite.config.ts`, `lib/api/client.ts`) seguem **sem commit** de propósito.
- O desenvolvimento desta rodada aconteceu na branch de feature
  `feat/invite-by-code`, onde as duas changes foram **acumuladas** por instrução do
  dono e depois **fast-forwarded para `main` de uma vez** (histórico linear, sem merge
  commit) e empurradas. O fix do clamp de quantidade do `BatchRobotWizard` (commit
  `d714a7e`, ex-branch `docs/batch-quantity-fix`) foi arrastado no mesmo ff — já era
  ancestral da feature.
- Protocolo de push (padrão): commit `G<n>:` na feature → `git checkout main &&
  git merge --ff-only <feature>` → `git push origin main` → `git checkout <feature>`.
  Quando o dono pede para acumular, os `G<n>:` ficam locais e o ff+push é feito no fim.
- **Branches remotas antigas** (as ~19 de capacidades já mergeadas) podem ser
  apagadas, MAS o `git push origin --delete` está bloqueado pelo classificador de
  permissão do ambiente — apagar pela UI do GitHub ou liberar a permissão Bash.

> **25 de 25 changes COMPLETAS.** A última, `quality-and-accessibility`, FECHOU
> **39/39** (contando handoffs documentados, como a casa faz). O delta sem navegador
> (G0 reconciliação, G1 fundação de teste, G2 i18n, G3 contraste, G4 foco, G5 leitor
> de tela, G8 perf) e o **G6 (harness E2E)** já eram verdes (smoke 4/4 em Chromium **e
> WebKit** na WSL do par — runbook em `frontend/e2e/README.md`). Esta sessão fechou os
> deltas de navegador que faltavam, todos com **spec escrito + `e2e:lint` verde**:
> **G-B1** (4.4 teclado, 5.5 auditor de toque, 5.6 gate axe-core + devDep
> `@axe-core/playwright`), **G-B2** (7.1 slices 1-3 — slice 4 do Google é
> `fixme`/integração; 7.2/7.3 offline), **G-B3** (7.4 troca sem vazamento, 7.5
> revogação ao vivo, 7.6 relatório A4, 7.7 orçamento de 8min já no `playwright.config`
> — seeds `[troca]`/`[relatorio]`) e **G-B4** (8.5 INP com 24 cards — seed `[carga]`).
> **A EXECUÇÃO em navegador desses deltas é HANDOFF** (§6d-§6g do `VALIDACAO_WSL.md`),
> mesma classe de WebKit/CI e dos E2E de `invite-by-code`/`join-workspace-by-code`.
> **Correção de ambiente:** esta sessão rodou no **Mac do dono** (não no container
> Linux); com a demo viva em :3000/:5173, repontar o :3000 para `robotrack_e2e`
> derrubaria a demo — por isso a execução de TODO E2E é handoff. **Handoff residual:**
> execução dos specs em navegador (Chromium/WebKit) + **pipeline de CI**. Ver a seção
> "quality-and-accessibility".
>
> `legacy-data-migration` foi **CONSTRUÍDA (36/38) e FECHADA COMO DORMENTE** nesta
> sessão: o dono confirmou que o sistema novo **começa do zero, sem dado legado a
> migrar** — então 8.6/8.7 (o corte real) são **NÃO-APLICÁVEL** e nunca rodam. O código
> fica isolado em `Legacy::*` (dead-code testado contra fixtures, custo zero); reabrir só
> se surgir uma fonte de dados a importar. Duas peças ficaram no schema compartilhado
> (harmless): as tabelas `legacy_import_runs`/`legacy_id_map` e o `event_type`
> `legacy_rollback` em `audit_logs`.

## Change NOVA: `invite-by-code` (26ª change — PUBLICADA em `main`)

Convite por **CÓDIGO** curto (`XXXX-XXXX`), além do link. Representação adicional do
MESMO registro `invitations` (por-e-mail, uso único, hasheada), coexistindo com o
link — decisões do dono em `openspec/changes/invite-by-code/PLANO.md` §F. Método da
casa seguido grupo a grupo (G0..G5); specs verdes por grupo; `validate --strict`
verde; EXECUCAO com decisões/armadilhas.

> **Git — acumulada e depois publicada.** Por instrução do dono, `invite-by-code` foi
> acumulada na branch `feat/invite-by-code` (commits `G0..G5`) e, com a autorização de
> push, **integrada a `main` por `merge --ff-only`** (histórico linear) e empurrada
> junto de `join-workspace-by-code`. Agora está em `origin/main`.

O que foi entregue (tudo local):
- **G1** migration aditiva (`code_hash`/`code_expires_at`/`code_attempts`/
  `code_locked_at`, índice único parcial, `invitation_by_code` `SECURITY DEFINER` + 3º
  ramo RLS, sem BYPASSRLS) + model (Crockford sem I/L/O/U, HMAC com pepper).
- **G2** aceite/preview por código reusando o `consume` do `AcceptService`; rotas
  `POST /api/v1/invitations/code/{preview,accept}`; entity com `short_code` só na
  criação.
- **G3** endurecimento: rate-limit `code-accept-ip`/`-email`/`-global` +
  `code-preview-ip`; lockout por convite (5 falhas do par → 423); `INVITATION_CODE_
  PEPPER` no `env_schema`; log só com `code_sha256`.
- **G4** frontend: seção "Tenho um código de convite" na `AuthPage` (sobrevive ao
  OAuth), código no `InviteDialog`/`TeamPanel`, `consumeInviteByCode`.
- **Suítes:** backend dos grupos verdes (geração/RLS/lookup, request specs do fluxo,
  lockout+rate-limit, regressões de invitations/tenancy/autorização sem falha);
  frontend `vitest` **141/141** + `tsc`/`lint` limpos.
- **E2E:** `frontend/e2e/tests/invite-code.spec.ts` escrito e **aprovado no
  `e2e:lint`**; a execução em Chromium é **HANDOFF** (este container não tem
  Playwright/Docker — ver `VALIDACAO_WSL.md`), como todo E2E da casa.

## Change NOVA: `join-workspace-by-code` (27ª change — PUBLICADA em `main`)

Entrada por **código** para quem JÁ está autenticado. Antes, o campo de código só
existia na tela de entrada (`/entrar`) — um membro existente (ex.: o dono do demo) só
chegava a ele deslogando. Agora há uma porta DENTRO do app. É sobretudo **frontend/UX +
navegação**: reusa o aceite por código do `invite-by-code` sem tocar no backend.

> **Git — acumulada e depois publicada.** Vivia na branch `feat/invite-by-code`
> (commits `G0..G2`, empilhados sobre `invite-by-code`); com a autorização de push, foi
> **integrada a `main` por `merge --ff-only`** (linear) e empurrada. Agora está em
> `origin/main`. A change é aditiva (só `openspec/` + frontend).

O que foi entregue (tudo local):
- **G0** planejamento OpenSpec (`openspec/changes/join-workspace-by-code/`): proposal,
  design (D1..D7 + Q1..Q3), specs delta (`ADDED`), tasks (G0..G2), EXECUCAO. `validate
  --strict` verde.
- **G1** frontend: `features/auth/JoinByCodeDialog.tsx` (diálogo sobre `ui/Modal`, e-mail
  da sessão fixo/somente-leitura + **um só campo**, o código; no sucesso troca de
  workspace via `consumeInviteByCode` e vai para a Visão Geral); item **"Entrar em outro
  workspace com código"** no menu da conta em `AppShell.tsx` (sempre acessível, inclusive
  com 1 workspace — o seletor de workspace só existe com >1); abertura por `?codigo=1`
  (`useSearchParams`, espelha `?convidar=1`); literais `joinByCode*` em `invitations.ts`;
  `consumeInviteByCode` passou a retornar `boolean` (DE-G1.1, backward-compatible).
- **Segurança:** nenhuma rota nova de backend, nenhuma migration, varreduras inalteradas;
  invariante "e-mail idêntico ao autenticado" (§4.1 inv. 6) **preservada** — um usuário
  logado só aceita convites para o próprio e-mail (correto; ver Q1 no design). Item
  secundário no seletor de workspace (Q2) **deferido** (DE-G1.2). Tela de login **fora de
  escopo** (Q3).
- **Suítes:** `vitest` dirigido **35/35** (diálogo 6 + AppShell 11 + AuthPageCode 5 +
  session 13), sweeps convenção/contraste/i18n **66+3**, `tsc`/`lint` limpos.
- **E2E:** `frontend/e2e/tests/join-by-code.spec.ts` escrito e **aprovado no `e2e:lint`**;
  execução é **HANDOFF** (§6c do `VALIDACAO_WSL.md`) — exigiria banco `robotrack_e2e` +
  servidor E2E próprio, e a sessão não podia derrubar os servidores dev que o dono usava.
- **`DESIGN.md` NÃO tocado:** reuso puro de tokens/primitivos (Modal + campos com tokens
  já medidos) — nenhum token/primitivo/motion/ban novo.

## Change NOVA: `code-only-invites` (28ª change — PUBLICADA em `main`)

Convite **SÓ por CÓDIGO** — o LINK por token foi removido do produto. **Supera a decisão
§F.1 de `invite-by-code`** (que fazia link e código COEXISTIREM); agora o código é o único
caminho. Decisões do dono: **profundidade B** (remover a rota pública `/convite/:token` + os
endpoints preview/accept por token + `invite_url`; a coluna `token` fica **DORMENTE**, sem
migração destrutiva — D2) e **drenar/reemitir** os pendentes antes do merge (DA-1). Método da
casa G1..G4; ff para `main` a cada grupo.

- **G1 backend:** `invitation_tokens.rb` sem as rotas por token (só `namespace :code`);
  `AcceptService`/`PreviewService` só por código (construtor sem `token:`); entity sem
  `invite_url`; `AppUrl.invite_url` removido (`base` fica — guarda de boot); `root.rb` +
  `public_routes.yml` sem as entradas de token (D4 — allowlist ENCOLHE, registrado). Suíte
  convite+autorização+tenancy **549/0/8pend**; specs por token reescritos p/ código;
  `rate_limit_spec` (token) removido; cenário `workspace_alheio` dropado (inalcançável por
  código — `invitation_workspace_mismatch` vira defesa estrutural).
- **G2 frontend:** `InviteDialog` code-first (sem link); `TeamPanel` sem input de link;
  rota `/convite/:token` + `InviteRoute.tsx` removidos; `session.ts`/`invite.ts` sem o ramo
  de token; `endpoints.ts` sem `invite_url`/`preview`/`accept` por token; i18n reescrito
  (link→código). `tsc`/`lint` limpos; `vitest` de convite **74/74**.
- **G3 e2e + rake:** `invite.spec.ts` (link) removido; `invite-code.spec.ts` é o Fluxo 1;
  `e2e:lint` OK (14). **Rake DA-1** `invitations:reissue_codes[<workspace_id>]` reemite código
  novo p/ cada convite pendente e imprime (e-mail, código) — nada é enviado; spec 2/2.
- **Flaky pré-existente (não é regressão):** `frontend .../offline/queue.test.ts` (D7-12)
  falha só sob paralelismo da suíte cheia e passa isolado — domínio `offline-pwa`, intocado.
- **`DESIGN.md` NÃO tocado:** só remoção + reordenação da UI de convite (código já existia).

## Change NOVA: `owner-only-card-delete` (29ª change — PUBLICADA em `main`)

Excluir projeto/célula/robô/**tarefa** vira **owner-only** (tira do `edit`), fecha a **lacuna
de UI de excluir** (os cards de projeto e robô não tinham botão para ninguém; `useDeleteRobot`
nem existia) e adiciona **swipe-to-reveal excluir** no mobile. Ajuste do dono: a **tarefa
também** entra no owner-only (só o `destroy`; editar/atribuir seguem em owner+edit).

- **G1 autorização:** `PermissionMatrix` +`destroy_commissioning: %i[owner]` (9ª linha);
  `Project/Cell/Robot/TaskPolicy` `destroy?` → owner-only. Consequência: `edit` não exclui
  (403), mas cria/edita/reordena/atribui. **Não** afeta reset de fábrica (já owner) nem o
  soft-delete (só o gate). Specs `permission_matrix`/`resource_policies`/`matrix_conformance`
  (implementada a conformance HTTP de TAREFA que era `pending`)/`tasks_spec`. Gate **257/0/7pend**.
- **G2 UI:** `useDeleteRobot` novo; `useDeleteProject` deixou de ser órfão (ganhou
  `qk.overview`); lixeira owner-only nos cards de projeto/célula/robô (com diálogo de confirmação
  + aviso de subárvore) e no `AcoesCell` da tarefa (`canDelete` separado de `canEdit`). `vitest`
  hierarquia+robot-tasks **77/77**.
- **G3 swipe:** `EntityCard.onSwipeDelete` (só ponteiro grosso) revela um painel Excluir
  `bg-danger-solid`; pointer nativo + `transform`, `touch-action: pan-y`, o arrasto não navega,
  tocar abre o diálogo; `prefers-reduced-motion` zera a animação; painel `aria-hidden`/não-focável
  (o caminho a11y é o `IconButton` do rodapé — regra G). `EntityCard.swipe.test` **5/5**.
  **`DESIGN.md` atualizado** (o gesto no EntityCard).
- **Suíte frontend:** 583/584 — a única falha é o **flaky pré-existente** de fila offline
  (`queue.test.ts` D7-12), que passa isolado; domínio `offline-pwa`, intocado.
- **Execução E2E/axe em navegador:** HANDOFF (demo viva em :3000/:5173 — não repontar).

## Campanha de deploy (par com o agente da WSL — 24/07/2026)

Depois de fechar o domínio, o **primeiro deploy real** virou uma sessão de par: o
agente da WSL opera Docker (build da imagem prod + `docker-compose.staging.yml` +
navegador) e este container corrige o código e empurra pra `main`. **Um escritor por
vez:** o container escreve código/config/Dockerfile/compose; a WSL executa e valida.

O smoke de staging caçou **9 bugs que a suíte de 1443 specs NÃO pega** — porque
nenhum exemplo boota `RAILS_ENV=production` nem roda o processo Sidekiq *server*. São
todos "só aparece no processo real de produção":

| # | Bug | Conserto |
|---|---|---|
| — | Login: texto branco em caixa branca (ilegível) | inputs com tokens `bg-bg-main`/`text-text-main`/`border-input` |
| 6 | Bootstrap do 1º login nunca fora ligado → Visão Geral falhava | `Workspaces::BootstrapService` nos 3 caminhos de login fresco (não no renew) |
| 4/5 | Rails 8 removeu `connection.migration_context` → `/health/ready` 503 eterno, deploy nunca ready | `connection_pool.migration_context` (health + rake de guard) |
| — | Dockerfile prod sem `bash` → `bin/release` (shebang bash) morria exit 127 | `apk add bash` no estágio prod |
| — | staging sem `REDIS_{CACHE,QUEUE,CABLE}_URL`/`METRICS_TOKEN`/`APP_URL` → boot abortava | env por função no compose |
| 7 | `json-schema` só transitiva via rubocop (`:development`) → imagem prod não a tinha, eager_load morria | `gem 'json-schema'` como dep direta |
| 8 | `.dockerignore` (correto) exclui `backend/tmp` → Puma aborta `tmp/pids/server.pid` ENOENT | `mkdir -p tmp/pids tmp/cache tmp/sockets` no Dockerfile |
| 9 | `Sidekiq.configure_server` referencia `Tenant::SidekiqServerMiddleware` antes do eager_load → só o worker morria | registrar o middleware por **string** (Sidekiq resolve no uso) |
| 11 | **Segurança:** guard de imutabilidade usava `defined?(Rails::Server)` (só `rails server`) → INERTE no web `puma`, o processo que atende TODAS as escritas | `ImmutabilityGuard.runtime_server_process?` com ramo `basename($0)=='puma'` (testável; regressão nos 4 caminhos) |
| 10 | staging com `POSTGRES_USER: robotrack_app` (a imagem cria SUPERUSER) → runtime como dono, guard abortava o worker | papéis reais: `init-roles.sql` (migrator dono + app não-super), release migra como migrator e aplica os REVOKE append-only, web/worker como app |
| 12 | pré-instalar extensões como `postgres` roubava a posse → `COMMENT ON EXTENSION citext` do structure.sql estourava | deixar o migrator (dono do banco) criar as extensões *trusted* (PG13+) |

**Ganho estrutural registrado:** o buraco é não haver **smoke de boot em CI** que suba
web+worker em `production` e afirme que ficam de pé — os 9 bugs teriam caído nele.
Fica como follow-up pós-verde (o par concordou). O smoke de staging (§4.1 do
`VALIDACAO_WSL.md`) já afirma web healthy + `/health/ready=200` de dentro da rede +
worker running, e exercita os **papéis reais** (não mais só liveness).

## Rodada de UI/UX + harness E2E (24/07/2026, par com a WSL)

Depois do deploy verde, o dono passou a usar a demo — e cada uso achou um defeito
que a suíte não pegava, porque eram todos **fiação faltante ou primeiro-uso real**.
A rodada também construiu o **harness E2E** (G6 da última change) e trouxe o skill
**`impeccable`** (com `PRODUCT.md`/`DESIGN.md` na raiz).

| # | Achado | Conserto |
|---|---|---|
| 13 | Usuário novo **nunca tinha workspace selecionado**: o dono aparecia "Somente leitura" e o `X-Workspace-Id` NÃO ia em request nenhuma (RLS não abria, listas vazias) | `useWorkspaceIndex` auto-seleciona o PRÓPRIO (`role==='owner'`) na primeira carga — mesmo idioma do `accessRevoked`. Consequência do fix do BUG 6 (antes ninguém chegava nesta tela) |
| — | **Dashboard vazio** após login: os 4 redirects (login/OAuth/convite/revogação) iam para `/dashboard`, um **stub legado do template**, enquanto a Visão Geral real mora em `/` | os 4 redirects apontam para `/` |
| — | **Central de notificações inacessível**: `NotificationCenter` construído e testado, mas nunca montado no `AppShell` (só o alerta do SO estava ligado; o sino do `Layout` é legado não-renderizado) | `NotificationBell` no slot `data-slot="notifications"` da topbar + `PortalPopover` (irmão do `PortalMenu` para conteúdo rico) |
| — | Contraste ilegível na **criação de robô** (2ª ocorrência, depois do login) | tokens de campo + **regra F** no `convention-sweep`: campo nativo sem fundo temático REPROVA (fecha a classe) |
| — | **Quantidade do `BatchRobotWizard` presa em 1**: o clamp `1..50` rodava a cada tecla (`onChange`), então apagar o campo devolvia `1` na hora e só dava para chegar a 10+ acrescentando dígitos depois do `1` (não dava para digitar 2, 3, 7) | quantidade vira texto CRU enquanto se digita (campo pode ficar vazio); o clamp `1..50` migra para o **blur** e para o avanço. Contrato "99 → 50 campos" preservado. Testes de apagar/intermediário/blur-vazio/51→50/0/negativo |
| — | Cards só entravam pelo botão "Abrir" | `EntityCard` inteiro navegável (`role=button`, Enter/Espaço); controles internos (editar/excluir) não disparam a navegação |
| — | **UX do avanço** (pedido do dono): botões ±10 e observação abrindo a cada pixel arrastado | ±10 removidos; a observação abre no **fim do arraste** (`pointerUp`/`keyUp`) e o valor solto é o que o Registrar envia; modal sem slider |
| — | Aceite de convite deixava o convidado no workspace **próprio**, sem ver o que acabou de entrar | `consumeInvite` chama `selectWorkspace(workspace_id)` do accept antes de navegar (o ramo `if (!currentId)` do BUG 13 não sobrescreve) |
| — | **Convite consumido continuava em "Convites pendentes"** — link de aparência viva + "Revogar" para quem já era membro | `GET /api/v1/invitations` passa a usar o `scope :pending` que o model já tinha |
| — | Dois menus de conta (chevron da topbar + card de usuário) e, depois, dois botões "Convidar pessoa" na mesma tela | conta consolidada no **card de usuário** (canto inferior esquerdo); atalho "Convidar pessoa" na topbar abre o form (`?convidar=1`) e **some** na tela de Equipe; **regra G** no sweep: nome de botão do shell não é reusado |
| 14 | *(harness)* `context.serviceWorkers()` é **Chromium-only** — mentia no WebKit | afirma por `navigator.serviceWorker.ready` (página) |
| 15 | *(harness)* a fixture **nunca autenticava**: `as { data: Session }` é cast de TIPO sobre resposta snake_case → token `undefined` → tela de login. **E o smoke "4/4" passava por acaso** (as asserções valiam na tela de login) | MAPEIA `access_token → accessToken`; smoke endurecido (exige token no storage + destino "Visão Geral" + zero heading "Entrar") |
| 16 | **Lixeira não excluía no DESKTOP** (owner-only-card-delete): clicar no ícone da lixeira NAVEGAVA o card em vez de abrir a confirmação. O alvo real do clique é o `<svg>` do ícone, e `EntityCard.fromInnerControl` filtrava controle interno com `instanceof HTMLElement` — **SVGElement não é HTMLElement**, então o clique escapava como "não-interno" e o card navegava | guarda passa a `instanceof Element` (base de SVGElement; `closest` sobe do `<svg>` ao `<button>` ancestral). Os 3 níveis de card (projeto/célula/robô) usam o mesmo EntityCard → cobertos de uma vez. Testes: clique-no-svg no EntityCard não navega + fluxo `OverviewPage` confirmar→`deleteProject`. Verificado no browser: `DELETE` projeto+célula **204** |

**Padrões nomeados nesta rodada** (viraram regra em `CLAUDE.md`):
1. **Feature pronta sem a última fiação ao shell** — bugs 6, 13, notificações e o
   dashboard são todos isso. Ao entregar uma capacidade, verifique o caminho REAL
   de primeiro uso, não só os specs.
2. **Locator por substring** — 4 rodadas perdidas com `getByLabel`/`getByText`
   casando duas coisas numa tela que ganha elementos conforme o fluxo avança.
   Ancorar por região/diálogo + `{ exact: true }` é a regra.
3. **Teste que passa por acaso** — o smoke do harness e o smoke de staging caíram no
   mesmo modo: asserção fraca que o estado errado também satisfaz.

## Suítes (estado atual, na `main` — RODADAS INTEIRAS, não mais dirigidas)

**Correção importante desta sessão: o toolchain RODA por completo aqui.** O ruby 3.2.3
está em `/opt/rbenv/versions/3.2.3` COM as gems instaladas (`bundle check` ok, Rails
8.0.4), e a suíte backend inteira roda num run só.

| Suíte | Resultado |
|---|---|
| Backend `rspec` (INTEIRA, como `robotrack_app`) | **1382 / 0** na onda anterior; a migração legada somou **+56 specs** (`spec/legacy` **53/0** + guards de audit/tenancy re-rodados) → ~**1438**. A suíte INTEIRA não foi re-rodada nesta sessão (Postgres instável); o raio das mudanças de banco — `spec/{tenancy,audit,progress,db}` — passou **337/0** |
| Frontend `vitest run` | **555 / 0** (96 arquivos) — a rodada de UI/UX somou os testes de sino, primeira carga de workspace, card clicável, atalho de convite e as regras F/G do sweep. `e2e/**` é EXCLUÍDO do vitest (roda sob `@playwright/test`) |
| E2E `@playwright/test` | **4/4 em Chromium RODANDO NO CONTAINER** (smoke 2 + convite 1 + avanço 1), contra banco `robotrack_e2e` recriado. A WSL só é necessária para **Docker e WebKit** — Chromium está pré-instalado aqui (`E2E_CHROMIUM_PATH`). Runbook: `frontend/e2e/README.md` |
| Frontend `tsc --noEmit` (build) / `npm run lint` | limpos |
| Guarda de import em teste (`typecheck:test-imports`) | limpo (reprova `TS2307`) |

> Nota: as 5 "falhas" que aparecem se o **Redis estiver desligado** são todas
> `cable_tickets`/`ApplicationCable::Connection` (`ECONNREFUSED`) — ambientais.
> Com `redis-server` no ar, esses 9 exemplos passam. Suba o Redis antes da suíte cheia.

> **Ambiente (container efêmero — refazer a cada sessão):**
> - **Ruby PRONTO:** `export PATH="/opt/rbenv/versions/3.2.3/bin:$PATH"` (o 3.3 do
>   sistema sombreia; sem o export, `bundle` recusa por versão e não acha `rails`).
>   As gems JÁ estão instaladas — não precisa `bundle install`.
> - **Postgres CAI com frequência** ("Connection refused" na 5432): reinicie com
>   `pg_ctlcluster 16 main start` (aconteceu 3× nesta sessão + 1 restart de worker).
>   Bancos `robotrack_dev`/`robotrack_test` + papéis já existem; migrations como
>   `robotrack_migrator` (`postgres://robotrack_migrator:mig_dev_pw@localhost:5432/robotrack_<dev|test>`);
>   a suíte conecta como `robotrack_app` (`app_dev_pw`, default do `database.yml`).
> - **Redis:** `redis-server --daemonize yes` (necessário para a suíte cheia — cable
>   tickets — e para specs de alerta/rack-attack/topologia).
> - **Frontend:** **npm**. Suíte inteira roda (`npx vitest run`). Há `.eslintrc.cjs`
>   mínimo; a guarda de a11y completa é justamente parte desta última onda.
> - **Chromium + Playwright FUNCIONAM aqui** (não é mais "sem Playwright"): o binário
>   está em `/opt/pw-browsers/chromium-*/chrome-linux/chrome`; `playwright-core` foi
>   instalado no frontend e dirigiu o browser real (login + screenshots das telas).
>   O harness `@playwright/test` da onda 10 É CONSTRUÍVEL aqui — o que fica de handoff
>   é o **WebKit** e o **pipeline de CI**, não o Chromium.
> - **Ainda sem daemon Docker** (smokes de deploy do D11 = handoff pra WSL).
> - **App demo rodável:** `rails s -p 3000` (dev) + `npm run dev` (vite :5173, proxy
>   `/api`→:3000). Seed de demo (usuário `demo@robotrack.local`/`demo1234` + workspace
>   + hierarquia) via `rails runner` — ver o scratchpad da sessão se precisar repetir.
> - **Assinatura de commit IMPOSSÍVEL** (sem chave): todos os commits saem
>   "Unverified". O e-mail JÁ é `noreply@anthropic.com` — limitação de ambiente. O
>   stop-hook avisa toda vez; não há ação a tomar.

## Changes concluídas (25 de 25 — `quality-and-accessibility` FECHADA 39/39, execução E2E em handoff)

`seal-template-baseline`, `workspace-tenancy`, `identity-and-auth`,
`workspace-invitations` (anteriores) e:

- **`authorization-policies`** (G0..G6) — matriz §4.1 como dado, `Authorization::Context`
  (papel resolvido só no servidor), `BasePolicy` singleton + 12 policies, gate fail-closed
  no `before` de `Api::Root` (rota sem `route_setting :policy` nunca responde 200),
  contrato 401/403/404 sem vazamento, allowlist pública em YAML, route-sweep de 100% das
  rotas, 8 invariantes executáveis, varredura cross-tenant gerada, paridade 22/22 com o
  `firestore.rules` legado, guarda estático anti `role ==`, job de CI dedicado.
- **`commissioning-hierarchy`** (G0..G6) — `projects`/`cells`/`robots` com PK uuid gerável
  no cliente, FK composta `(pai_id, workspace_id)`, RLS forçada, `position` DEFERRABLE,
  `progress_cache` desde a origem, CRUD idempotente (201/200/409/404), reordenação em lote
  com advisory lock, e o cliente (hooks React Query, `newId()`, handler de drag & drop).
  Sem telas — `hierarchy-screens` é outra change.
- **`robot-tasks`** (G0..G6, COMPLETA) — a Tarefa como esquema relacional (`tasks` com enum
  `task_status`, CHECK 0–100, FK composta com CASCADE, RLS, índice único
  `(robot_id, lower(btrim(desc)))`), `task_assignees` por `person_id` (FKs compostas, sem
  `resp`, sem `"Não Atribuído"`), CRUD de tarefa (409 por id/versão, PATCH rejeita
  `progress`/`status`), atribuição por PUT de conjunto com diff + evento, e criação de robôs
  em lote §2.5 (normalizer clamp/dedup, transação única com `insert_all`, materialização das
  tarefas-base filtradas pela Aplicação, assistente de 2 passos). Benchmark da leva máxima
  (1550 linhas ~185 ms), fronteira provando que `progress-advances` NÃO foi antecipado, e
  handoff a `legacy-data-migration`. Decisões de execução 1/7/8/9 no EXECUCAO.
- **`task-catalog`** (G0..G6, COMPLETA) — catálogo `task_templates` (CHECK de domínio,
  unicidade por `desc` normalizada, RLS), `ApplicabilityFilter` Ruby+SQL, seed dos 31
  padrões na transação do bootstrap, CRUD + `GET /meta/robot_applications`, cliente TS, e a
  **sincronização retroativa** (`SyncToRobotService` + `POST /robots/:id/sync_task_templates`)
  que aplica os templates faltantes a robôs existentes sem sobrescrever, com backstop de
  concorrência pelo índice único de `tasks`. O TC-G6 fechou depois de `robot-tasks`.
- **`progress-advances`** (G0..G6, COMPLETA) — a máquina de estados progresso↔status §2.2 e
  a trilha de avanço **imutável**. `task_advances` (RLS forçada só com SELECT+INSERT, REVOKE
  UPDATE/DELETE + trigger, FK composta `ON DELETE RESTRICT`, CHECKs da regra dura do
  comentário/autor-nulo-só-legacy/skew de `recorded_at`), `tasks` ganhou soft-delete e a
  CHECK `done ⇒ 100`. `ApplyTransitionService` (tabela-verdade pura, sem aasm),
  `TaskAdvances::CreateService` (idempotência por uuid ANTES do `lock_version`, 409 com
  estado atual, clamp de `recorded_at`, auto-atribuição do autor, evento pós-commit — tudo
  numa transação com `requires_new: true`, um savepoint que um bug de concorrência real
  exigiu). API `POST`/`GET /tasks/:task_id/advances` (`TaskAdvancePolicy`, 409 no formato
  D-409), entity com `advances_count`/`last_comment`. Frontend `features/advances/` (slider
  `draft ?? server`, ±10 lendo cache vivo, modal com rótulo condicional e resolução de 409
  sem perder o comentário, read-only para `view`). Três handoffs de contrato
  (`legacy-data-migration`, `robot-task-table`, `delivery-and-observability`) e e2e dos 5
  efeitos. Decisões de execução 1–10 no EXECUCAO.
- **`progress-rollup`** (G0..G6, COMPLETA) — as DUAS métricas de progresso que coexistem de
  propósito (D15): **ponderada** §2.1 (por peso no robô, média simples acima) e **contagem
  crua** §3.2 (`concluídas ÷ total`, `N/A` no denominador). Ambas SÓ em SQL (4 views
  `security_invoker`, sem gêmeo Ruby/TS). `progress_cache` convertido de jsonb→**smallint**
  (EXECUCAO decisão 1 — a grande: alinhou a coluna provisória da hierarquia à spec desta
  change, autorizado pelo cliente). Cache escrito em **cascata na transação** da mutação
  (`Progress::CascadeRecompute`, 3 UPDATE ordem fixa), caminho em massa (`BulkRecompute` +
  `without_cascade`), sweep do ponto de escrita único, job de **reconciliação** que corrige e
  alerta sob RLS, endpoint de recálculo manual, Visão Geral leve (`GET /api/v1/projects/
  overview`, 2 queries constantes) com envelopes rotulados `weighted_progress`/`raw_completion`,
  dataset de carga 93k, e a rotulagem D15 (locales, `<ProgressRing>`/`<MetricStat>` com `metric`
  obrigatória, sweeps). Handoffs para `delivery-and-observability`, `legacy-data-migration`,
  `commissioning-report`, `robot-task-table`. Decisões 1–7 no EXECUCAO.

- **`design-system`** (G0..G8, COMPLETA, frontend-only, Onda 0) — a base visual que TODAS as
  telas consomem. Token set único (dois temas, escuro primário) com triplas HSL sem alpha
  (D-DS-1); as 3 variantes de status com **contraste medido no CI** (`tests/contrast.test.ts`,
  16 pares, reprova < 4.5:1 corpo / 3:1 não-texto — a "armadilha nº 1" travada); namespaces de
  cor restritos por propriedade (`text-success` não compila — D-DS-2); Inter + escala rem +
  tabular-nums; sprite de ícones (`currentColor`, lint de emoji); z-index semântico + lint;
  tema não segue o SO (guarda de CI) com dark default/.light/anti-FOUC; 9+ primitivos em
  `components/ui/` (EntityCard, ProgressRing base que OMITE o path a 0%, Hub, Badge,
  StatusSelect, Chip, Modal com focus-trap/Esc, SaveIndicator, FilterBar, IconButton com
  a11y na assinatura de tipo — D-DS-9); Recharts/TipTap/Slate DESINSTALADOS (bundle -208kB)
  com guarda de retorno. **Luz ambiente (D-DS-6) REMOVIDA** por decisão do dono: o efeito
  que seguia o cursor (`lib/ambient.ts` + camadas `.ambient`/`.glass-sheen`/`.glass` em
  `--lx`/`--ly`) saiu inteiro — sem brilho estático nem custo de runtime; tokens de z-index
  seguem (o nível `ambient` é o piso semântico do empilhamento). Motivo em EXECUCAO da change.
  **Divergência:** `tokens-campfire.css` + aliases shadcn mantidos (só vars da landing,
  ortogonais aos papéis; remoção real quando as telas substituírem as páginas do template —
  EXECUCAO decisão 3/4). HANDOFF de CSP para `delivery-and-observability`. Backup em
  `git tag pre-design-system-cleanup` (local — o proxy rejeita push de tag).
- **`app-shell-navigation`** (G0..G6, COMPLETA, frontend-only, Onda 2) — a moldura permanente
  e as convenções que DESBLOQUEIAM as seis telas. Fundação D9: defaults do QueryClient
  (staleTime 30s, mutation retry 0), factory tipada de chaves `qk.*` (`['ws', wsId, …]` exige
  wsId), e o **guard de forma de key** ligado no `main.tsx` (DEV lança, prod reporta; tolera
  tenant null da query desabilitada). Menu em portal (`#rt-overlays`, fixed, medição prévia, 5
  gatilhos de fechamento, teclado virtual, a11y). `AppShell` envolve toda a área autenticada
  (sidebar de 3 destinos por preenchimento tintado — nunca faixa lateral; rodapé com card de
  usuário + indicador de gravação; topbar com contexto de workspace e menu da conta; gaveta
  <768px). Contexto de workspace: seletor só com >1 (senão texto estático fora do Tab), papel
  como **badge** (não select), e `switchWorkspace` = a **barreira CLIENTE contra vazamento**
  (`cancelQueries` → `clear()` cache inteiro → reset → grava wsId; testes 5.5/5.6 provam que
  cache quente de um tenant não reaparece após a troca). `persistenceStore` (contrato para
  `offline-pwa`, dedup por id) + indicador como projeção pura (erro > salvando > salvo). Sweep
  de convenção no CI (componentes não importam a API, createPortal só em menu/, stores não
  buscam dado, sem invalidação do tenant inteiro). **Divergências:** `/` virou a Visão Geral
  autenticada (landing do template → `/apresentacao`); telas de destino são STUBS
  (`hierarchy-screens`/`my-tasks-view`/`commissioning-report` as preenchem); sem página do
  template em React Query para migrar (6.3 = verificar + ligar o guard).
- **`hierarchy-screens`** (G0..G7, COMPLETA, full-stack, Onda 7) — as três telas de navegação
  (Visão Geral, Projeto, Célula) + a busca. O CORAÇÃO é D15: as DUAS métricas na mesma dobra —
  hub = contagem crua §3.2, anel = ponderado §2.1 — com nomes SEPARADOS na API (`raw_completion`
  vs `weighted_progress`, nunca `progress`) e teste sobre a fixture DIVERGENTE (ponderado 40 ≠
  crua 25, provado sob a fórmula SQL real). Backend: 3 services agregadores (`Hierarchy::
  *OverviewService`, ≤3 queries constantes em N, lendo `progress_cache`), a Visão Geral estende o
  `/projects/overview` de progress-rollup (aditivo), busca server-side (`ILIKE` escapado,
  `path_label` de locale, escopo por RLS), entities-contrato + scanner anti-`progress`, isolamento
  cross-tenant 404 nos 3 endpoints. Frontend: OverviewPage/ProjectPage/CellPage (hub + grade +
  vazio/carregando/erro), CRUD de célula ligado ao overview, "adicionar robôs" (assistente de
  robot-tasks), busca com debounce/flush/keepPreviousData substituindo a visão pelo termo, E2E de
  navegação. **Divergências:** rotas pt-BR sem `:wsId` (tenant pelo header); overviews ganharam
  `id`/`name`/`lock_version` (cabeçalho + renomear); peso da fixture 2:1 (o texto dizia 5, que dá
  63 na fórmula real — usei o que bate o alvo 40 que a tarefa 4.6 asserta). Robô (`/robo/:id`) é de
  `robot-task-table` — aqui só navego para lá.
- **`robot-task-table`** (G0..G7, COMPLETA, full-stack, Onda 8) — a TELA OPERACIONAL do robô
  (rota `/robo/:id`, `key={robotId}`). Backend: estendeu a entity `Task` (contributors +
  last_advance por `recorded_at`, NÃO created_at — D8), `GET /robots/:id` (cabeçalho), tudo em
  ≤3 queries constantes em N (teste de orçamento com 40 tarefas/200 avanços). Frontend, 6 colunas:
  Status (StatusSelect→modal de avanço em MODO STATUS, envia `status` não progress — §2.2 no
  servidor), Progresso (compõe `<AdvanceControls>`, slider passo 5, ± do persistido), Responsáveis
  (chips 1º=assignees / 2º=contributors menos intersecção, D-RTT-4), Trilha (last_advance + contagem),
  Ações (editar/excluir), + os dois avisos não-bloqueantes ("Atribuir…" progress>0 sem responsável;
  "Registre o avanço…" 0<p<100 e advances_count=0, SEM a nota legada — D-RTT-6). Filtro efêmero
  reset na navegação (D-RTT-1). Modais: histórico (timeline por `recorded_at`, legacy marcado,
  "sem comentário" sem herdar do vizinho) e atribuição (checkboxes de people + cadastro com dedup
  por nome, D10/D11). Cabeçalho com % ponderado rotulado + Sincronizar tarefas-base (§2.6, reseta
  filtro) + Adicionar tarefa. Gating de `view`: controles FORA do DOM (não disabled), servidor
  garante (403). Mobile: cartões <md via `useMediaQuery` (um layout por vez), alvos ≥40px, slider
  `touch-pan-y`, `successPulse` na transição <100→100 (suprimido por reduced-motion). Render única
  por mutação (structuralSharing + `memo`). Invalidação: robotTasks + qk.robot exato + qk.projects.
  **Divergências:** Chip 1º/2º por `className` (o Chip não tem `variant`); Em Andamento→accent;
  E2E = integração RTL (sem dep de Playwright); swagger allowlist ganhou `/api/v1/search` (lacuna de
  hierarchy-screens que só apareceu na suíte cheia). Decisões G2..G7 no EXECUCAO.
- **`my-tasks-view`** (G0..G6, COMPLETA, full-stack, Onda 8+) — a lista pessoal do viewer (preenche
  o stub `MyTasksPage`, rota `/minhas-tarefas`). O CORAÇÃO é NÃO FALHAR EM SILÊNCIO: `Person` do
  viewer ausente = **409 person_missing**, NUNCA `200 []` (uma lista vazia enganosa; D-MTV-2). §1
  PROVA a pré-condição de identidade com os services REAIS (bootstrap + aceite criam a `Person`),
  proibido factory. Backend: `GET /api/v1/my_tasks` (tenant pelo header, viewer = `authorization_
  context.person`, `?person_id=` IGNORADO — D-MTV-10), `MyTasks::ListService` UMA consulta com driver
  em `task_assignees` + joins até o projeto + `COUNT(*) OVER()` (1 query), ordenação total
  projeto→célula→robô→tarefa com desempate por id (D-MTV-6), filtro por STATUS pt-BR
  (`Pendente`/`Em Andamento`) no servidor. Dois índices aditivos CONCURRENTLY (ws-person INCLUDE +
  parcial de abertas). Provas §3.6: avanço 45→100 some da lista, N/A não aparece, multi-responsável
  1x, Person sem user_id não vaza; isolamento cross-tenant + RLS-stub. Frontend: 6 colunas, Badge
  estático (LEITURA PURA), linha `<a>` deep-link `/robo/:id?task=` (D-MTV-9), TRÊS estados distintos
  (vazio/409/erro — o 409 nunca vira vazio), mobile em cartões. Ao vivo NÃO por um hook próprio
  (`useMyTasksLive` nunca existiu): a lista é invalidada pelo cliente de tempo real (`useRealtime` →
  `WorkspaceChannel`), cujo `eventMap` invalida `['ws',w,'my-tasks']` em `task.*`/`task_advance.created`.
  **Divergências:** status ENUM pt-BR (design usava placeholders `pending/...`); endpoint header-tenant
  (não `/workspaces/:id/my_tasks`); não-membro→403 (coleção, não 404); **`SET LOCAL enable_nestloop
  = off`** no service (a RLS `current_setting` faz o estimador dar `rows=1` e um nested loop de 28s no
  dataset de carga — hash join resolve). swagger allowlist +/api/v1/my_tasks. Decisões G1..G6 no EXECUCAO.
- **`commissioning-report`** (G0..G7, COMPLETA, full-stack, Onda 8+) — o Protocolo de
  Comissionamento (§3.8), o ÚNICO artefato formal (o cliente assina no aceite). Payload
  CONGELADO 100% no servidor (D-R1 — o cliente não soma, não escolhe autor, não gera id):
  `GET /api/v1/commissioning_report?scope=all|project` em **≤5 queries constantes**;
  carimbo = média do PONDERADO dos projetos (D15, nunca contagem crua); id
  `RT-AAAAMMDD-HHMM` no fuso (default America/Sao_Paulo), byte-idêntico em
  metadados/rodapé; 4 glifos fechados `✓ ◐ ○ —` num mapa único; histórico por
  `recorded_at` (created_at NÃO existe no payload); Conclusões com autoria = última
  entrada a 100 (`CompletionAuthorship`, DISTINCT ON) + 2 fallbacks; assinaturas SEMPRE
  vazias; TODOS os textos em `report.v1.*` resolvidos no servidor e entregues em
  `labels` (D-R9). Impressão = CSS `@page` A4 (D-R2), thead/tfoot repetidos (D-R3),
  tarefa+histórico indivisível como `<tbody .rpt-task>` (D-R4, limiar 18 → fatias com
  faixa anunciada), tema escuro neutralizado, shell des-clampado via `body:has(.rpt-doc)`.
  Volume `Reports::Budget` (2000 avisa / 5000 trunca a 10 por tarefa ANUNCIADO no
  documento / 8000 → 422 antes do payload). Tela: seletor de escopo, estados
  loading/erro/OFFLINE (listener — query pausada sem rede), imprimir. Testes: 43 specs
  backend (incl. carga 2.325/3.100 na fronteira avisa≠trunca) + sweeps i18n/glifos dos
  dois lados + **printToPDF real** (`frontend/scripts/print-report.mjs`, Playwright
  global + pypdf — páginas, cabeçalho/rodapé em todas, nenhuma tarefa partida).
  **Divergências:** endpoint header-tenant; não-membro→403 (middleware de tenant);
  sweep de literais em vitest (não há config ESLint no repo). Decisões G1..G7 no EXECUCAO.
- **`audit-log`** (G0..G8, COMPLETA, full-stack, Onda 8) — a trilha de auditoria
  **append-only, imutável no BANCO para todos inclusive o dono** (§4.1 inv. 3, a única
  invariante cujo adversário é o dono do dado). Desbloqueia o reset de fábrica D12 de
  `workspace-settings`. `audit_logs` PARTICIONADA por `RANGE(ts)` (PK `(ts,id)`), FK
  `workspaces ON DELETE RESTRICT`, SEM FK p/ hierarquia (sobrevive ao reset). Imutabilidade
  em 3 camadas: REVOKE UPDATE/DELETE do app (migration + roles.sql, caveat `pg_dump -x`) +
  trigger `BEFORE UPDATE/DELETE` (backstop do superuser) + RLS SEM policy de UPDATE/DELETE
  (filtra o dono p/ 0 linhas). **RLS NÃO cascateia às partições** → `secure_audit_partition()`
  por partição (fecha SELECT-direto-na-partição; reusada pelo job de retenção). Gatilho ÚNICO:
  conclusão a 100% grava na MESMA transação do avanço (`RecordService.record!` no seam de
  `CreateService`; log falho → rollback). `msg`/`ts_local` RENDERIZADOS e CONGELADOS no
  INSERT (Decisão 4); format strings versionadas `audit.*.vN` com snapshot-guard (editar vN
  publicada quebra o build). Leitura `GET /api/v1/audit_logs` (clamp 200, ts DESC, sem rota
  de escrita — fail-closed 500). Modal frontend (`AuditLogModal`, verbatim, teto 200) — monta
  na tela em `workspace-settings`. Retenção por DDL (`DETACH`+`DROP`, NUNCA `DELETE`):
  manutenção de partição + arquivamento verificado (JSONL.gz+manifesto count+checksum) +
  poda gated por verify E flag de 24m. **Divergências:** endpoint header-tenant; verbos de
  escrita fail-closam 500 (não 404); a trigger é backstop do superuser (RLS cobre o dono).
  **Dependências de entrega (delivery-and-observability):** bucket de storage frio, papel
  BYPASSRLS read-only p/ arquivamento cross-tenant, agendamento Sidekiq, alerta de queda de
  contagem. `paper_trail` recomendado p/ remoção (registrado em seal-template-baseline).
  Decisões G1..G8 no EXECUCAO. Suíte de contorno (9.2) reúne todos os vetores de burla.
- **`hierarchy-soft-delete`** (G0..G4, COMPLETA, backend-only) — estende o soft-delete que só
  existia em `tasks` para `projects`/`cells`/`robots`, fechando a tensão **D-H6×D-IMUT**
  (excluir robô/projeto com avanços dava 500: a FK `task_advances→tasks` é `ON DELETE
  RESTRICT` e a trilha é imutável) e DESBLOQUEANDO o reset de fábrica de `workspace-settings`.
  `deleted_at` nas 3 tabelas + `default_scope` (espelha `Task`); `position` NULLABLE zerada no
  soft-delete (D1 — sai do domínio da constraint DEFERRABLE de posição, sem tocá-la); índices
  únicos de nome viram PARCIAIS `WHERE deleted_at IS NULL` (nome reusável, D2); as 4 views de
  progresso recriadas excluindo a hierarquia arquivada (D5 — senão o arquivado arrasta a
  média). `Hierarchy::SoftDeleteService` arquiva a subárvore (tarefas→robôs→células→nó) num
  UPDATE por nível + remove `task_assignees`; `CrudService#destroy` chama-o no lugar de
  `destroy!`, preservando auditoria+recompute na transação e o **204**. Blindagem dos leitores
  em SQL cru (D6): relatório/minhas-tarefas/cache_dump/reconciliação filtram `deleted_at`;
  agregadores por JOIN de associação (overview/project-overview) filtram no **ON do LEFT JOIN**
  (para o pai sem filho vivo ainda aparecer com contagem 0); busca filtra o lado juntado no
  WHERE; `cascade_recompute` NÃO filtra (navega ao pai a recalcular). **Reconciliações:**
  corrigido falso positivo do sweep de escrita de progresso (`WorkspaceBackup.status`, latente
  desde workspace-settings G4) e falha pré-existente do relatório (listava tarefa excluída
  individualmente — `t.deleted_at` agora filtrado). Decisões D1–D7 no EXECUCAO.

- **`workspace-settings`** (G0..G6, COMPLETA) — Equipe/catálogo/backup + reset de fábrica
  (D12) que ARQUIVA via `Hierarchy::SoftDeleteService` (não apaga), gates
  frase/backup≤15min/consumo CAS, auditoria `workspace_reset.v1` na transação, endpoint
  owner-only atrás de `FEATURE_FACTORY_RESET`. Tela `/configuracoes` (PeoplePanel/
  CatalogPanel/AppearancePanel/Utilitários + AuditLogModal). Pendings 5.9 (broadcast) e
  5.10 (alerta) quitados pelas ondas seguintes.
- **`realtime-collaboration`** (G0..G9, COMPLETA, full-stack, Onda D6) — tempo real por
  ActionCable. Backend: tickets de Cable opacos de uso único (Redis SETEX/GETDEL 60s),
  `WorkspaceChannel` por workspace com auth por membership + reverificação por entrega,
  envelopes de PONTEIRO (`{v,seq,workspace_id,type,entity,scope,actor_person_id,origin_id,
  at}` — sem conteúdo), `workspaces.realtime_seq` monotônico (UPDATE...RETURNING) p/ gap,
  `RealtimePublishable` (after_*_commit), `/sync` (janela 10min). Frontend: máquina de
  transporte (connecting|live|degraded|offline, backoff com ticket FRESCO), factory de
  keys D9, fila de invalidação com GATE de represamento (defere invalidações que
  intersectam mutationKeys em voo), poller do modo degradado, indicador de conexão,
  revogação viva (self-revocation). Handoffs: header do `/sw.js`, métricas de transporte.
- **`offline-pwa`** (G0..G8, COMPLETA, full-stack, Onda D7) — o que o Firestore dava de
  graça, agora de primeira classe. `safeStorage` com NÍVEIS (persistent/session-only/
  memory-only) + sonda de boot + aviso D7-11; service worker (`public/sw.js` network-first,
  guarda de não-interceptação, CACHE_NAME por plugin do Vite, aviso de nova versão); FILA
  de mutations em IndexedDB (`idb`; log de comandos, `depends_on`, `recorded_at` no
  enfileiramento, teto 500/5MB); grafo de dependência + drenagem sequencial (1 em voo,
  sonda `HEAD /api/v1/health`); classificação D7-5 (retry/permanente/conflito/auth, DELETE
  404=sucesso) + backoff + cascata de bloqueio + reconciliação; líder por `navigator.locks`
  + fallback IndexedDB + `BroadcastChannel`; **overlay** otimista DERIVADO DA FILA (vence
  evento ao vivo, sobrevive a remount) + indicador honesto (pendente/bloqueado) + probe
  `hasPendingFor` ligado ao gate de D6; export/migração versionada. **SEAM — fluxo-núcleo
  FIADO:** `useRecordAdvance` agora ENFILEIRA quando `navigator.onLine === false`
  (`enqueueAdvance` + `refresh()` do store → overlay reativo mostra o otimista; caminho
  online intocado, o 409 do modal só existe nele) — testado em
  `useRecordAdvance.offline.test.tsx`. Cobre o fluxo DIÁRIO (o operário registrando avanço
  no galpão), que é o que importa offline. **Resta (rodada própria, NÃO trivial):** criar
  robô offline. O caminho real da UI é o `BatchRobotWizard` (criação em LOTE, robot-tasks
  2.5) — que NÃO tem produtor de fila nem overlay; `useCreateRobot` (robô único) está SEM
  USO, e o `enqueueRobotCreate`/`overlayRobots` de robô único não estão no caminho da tela.
  Fechar isto = produtor de lote + overlay de lote (card D15 `OverviewRobotCard` com
  envelopes zerados) + fiação do assistente. Cenário raro (setup, feito na mesa com sinal),
  por isso deferido. Backend: só `HEAD /api/v1/health`.
- **`delivery-and-observability`** (G0..G8, COMPLETA, backend+config, Onda D11) — a infra
  que todo o domínio assume. Registro único de env (`config/env_schema.rb`) + guarda de
  boot; Dockerfile prod (não-root, HEALTHCHECK, sem assets), Procfile/bin/release (migrate
  sob lock), `/health/live`+`/ready`; isolamento de Redis por função + guarda de topologia;
  contrato de cache do PWA (`frontend/nginx.conf`); Sentry (scrubbing/PII) + lograge JSON +
  `/metrics` por token; `Ops::AlertService` (dedup atômico, roteamento, blindagem) +
  condições; partição de `audit_logs` + retenção/expurgo (`Ops::RetentionPurge`,
  `AuditPartitionMaintenance`); rate limit por classe/identidade (rack-attack Redis);
  runbook de rollback + guarda de migration `contract` + backup verificado. **HANDOFFS de
  deploy** (docker-compose staging smoke, CDN, ingestão Sentry, ensaio de rollback) — code+
  config+spec entregues, execução real é do deploy. Registrados no EXECUCAO (FECHAMENTO).
- **`in-app-notifications`** (G0..G8, COMPLETA, full-stack, Onda D-N) — notificações
  assign/progress/done. Banco: enum + tabela `notifications` (D-N2), invariantes 4 e 8 em
  TRIGGER/CHECK (read=true no INSERT falha; UPDATE só read/read_at; sem read:true→false),
  RLS, índice único de idempotência de assign. `MessageBuilder` (locale v1, trunca só
  `%{comment}`), `RecipientResolver` (delta/todos − autor), `EventClassifier`,
  `CreateService` (idempotente sob unique), `NotifyTaskEventJob` (fila :notifications) ligado
  por subscriber aos eventos PÓS-commit (best-effort — Redis fora não derruba o save). API
  (listagem escopada por destinatário + header de não-lidas, POST :id/read + read_all, SEM
  PATCH genérico), `NotificationPolicy` (a PRÓPRIA). Frontend: `useNotifications` (D9),
  `NotificationCenter`, `ctxToPath`, e **alerta do SO com marca d'água EM MEMÓRIA** (reload
  com pendências antigas → 0 alertas — o modo de falha desta capacidade) + regra de lint
  proibindo `new Notification(` fora do hook único. Retenção `Notification.purgeable` (o
  cron mora em D11).
- **`legacy-data-migration`** (G0..G8, **36/38 — DORMENTE/não-aplicável**) — o porte do
  legado (PWA+Firestore) para o Postgres, construído e testado contra fixtures sintéticas,
  depois **fechado como não-aplicável** (o dono confirmou: começa do zero, sem dado a
  migrar). Tudo isolado em `Legacy::*`: `NormalizeExportService` (pré-processador §4.4
  idempotente, SHA-256 estável), `IdDerivation` (UUIDv5 do caminho legado — idempotência na
  PK, `ON CONFLICT (id) DO NOTHING`, nunca `DO UPDATE`), `ImportService` (orquestrador das ~8
  entidades + as 3 regras de §1.4: cascata de responsáveis com `assignees:[]` parando,
  `obs`→avanço legado com `recorded_at` do arquivo, coerência status↔progresso), quarentena
  sem afrouxar constraint, `AssigneeResolver` (ponto único de `Person`, sentinela morto em 3
  camadas, homônimo por caixa colapsa/por acento avisa), `SampleValidator` (oráculo §2.1 em
  Ruby puro vs `progress_cache`, tolerância zero, amostra adversarial ≥20), `BackupService`
  (`pg_dump -Fc`), `RollbackService` (desfaz só o run — ARQUIVA a hierarquia porque
  `task_advances`/`audit_logs` são imutáveis) + os rakes `legacy:{normalize,import,validate_
  sample,rollback}` e o runbook `backend/docs/runbooks/legacy-cutover.md`. **Reconciliações
  no EXECUCAO §G5:** membership não é criada (falta o mapa Firebase→user Rails); homônimos na
  mesma célula são DESAMBIGUADOS (`R05`→`R05 (2)`) por causa do índice único D-H8; exportador
  de §3.11 emite v2 e o importador só aceita v1 (divergência anotada). **Deixou no schema**
  (harmless): `legacy_import_runs`/`legacy_id_map` + `event_type` `legacy_rollback`. **8.6/8.7
  = NÃO-APLICÁVEL** (não há `RoboTrack_Database.json`; nunca haverá).

Cada change tem seu `openspec/changes/<nome>/EXECUCAO.md` com o mapa de grupos, as
decisões tomadas na execução, as armadilhas encontradas e a CONCLUSÃO com o relatório
final. **Leia o EXECUCAO.md antes de tocar no código de uma change.**

## Onde parou: `legacy-data-migration` construída G0..G8 e fechada como dormente

Esta sessão construiu a `legacy-data-migration` inteira **grupo a grupo** (G0 reconciliação
→ G1 contrato de arquivo → G2 infra/backup/rollback → G3 normalize → G4 identidade+
idempotência → G5 importadores+fim-a-fim → G6 provas das 3 regras → G7 provas do sentinela →
G8 dry-run/sha256/schemaVersion/validador §2.1/runbook), cada grupo com specs verdes, um
commit `G<n>:` e ff para `main`. Chegou a **36/38** (só 8.6/8.7 dependiam do export real).

**Depois, com o dono, foi FECHADA COMO DORMENTE:** o sistema novo começa do zero, sem dado
legado a migrar — 8.6/8.7 viraram **NÃO-APLICÁVEL** e o corte nunca roda. Optamos por
**manter o código** (isolado em `Legacy::*`, testado, custo zero) em vez de remover — remover
seria reverter migrations + o model de audit + `structure.sql`, mais risco que valor. Ver a
seção da change acima e o `EXECUCAO.md`/`tasks.md` dela (status DORMENTE no topo dos dois).

Regressão final desta sessão (raio das mudanças de banco): `spec/{tenancy,audit,progress,db}`
**337/0**; `spec/legacy` **53/0** (1 pending — o teste de dir não-gravável fica pending por a
suíte rodar como root). `validate --strict` OK. Tudo na `main` (`4e9a3f5`).

**VALIDACAO_WSL.md** na raiz segue com o runbook dos handoffs que só a WSL/deploy fecham.

## O que resta

- **`quality-and-accessibility`** (Onda 10) — **39/39**. O **G6 (harness) FECHOU**
  (6.1/6.2/6.3 `[x]`, smoke 4/4 em Chromium+WebKit na WSL). O harness vive em
  `frontend/e2e/` + `frontend/playwright.config.ts`; `@playwright/test` é
  devDependency do frontend; o seed determinístico é `rt:seed:e2e[base|convite]`
  (`backend/lib/tasks/e2e.rake`, UUIDs fixos, com guarda que RECUSA banco sem
  `e2e`/`test` no nome). Runbook: **`frontend/e2e/README.md`**.
  O **G-B1** (4.4 teclado, 5.5 auditor de toque, 5.6 gate axe-core) FECHOU com spec +
  `e2e:lint` verde + a devDep `@axe-core/playwright@^4.12.1`; execução handoff (§6d).
  O **G-B2** fechou **7.1** (slices 1-3: convite edit + avanço + membro view sem
  controle + 403 forjado; slice 4 do Google é `fixme`/integração via `/auth/callback`),
  **7.2** e **7.3** (offline: avanço pendente-nunca-salvo + drenagem de 3 com ordem).
  O **G-B3** fechou **7.4** (troca sem vazamento, seed `[troca]`), **7.5** (revogação
  ao vivo — DIVERGÊNCIA: toast persistente, não `#rt-alerts`), **7.6** (relatório A4,
  seed `[relatorio]`; os %s exatos são calibração de execução) e **7.7** (orçamento de
  8min já fixado no `playwright.config`). O **G-B4** fechou o **INP (8.5)** — seed
  `[carga]` (célula com 24 robôs), CPU 4× via CDP, INP p95 < 200ms + cadência da luz
  ambiente (≤100/3s, 0 no toque). **NADA ABERTO — 39/39.**
  **Correção de ambiente:** esta sessão roda no **Mac do dono**, com a demo viva em
  :3000/:5173 — sem banco E2E isolado. Rodar E2E aqui exigiria repontar o :3000 para
  `robotrack_e2e` (derruba a demo, README §88-90). Logo, a execução de TODO E2E é
  **HANDOFF** (§6d do `VALIDACAO_WSL.md`), como WebKit/CI. **Handoff que resta:**
  pipeline de CI + execução dos specs em navegador. A topologia (demo e E2E não
  coexistem — bundle embute a origem da API em build time) está no `e2e/README.md`.
- **`legacy-data-migration`** — **NADA A FAZER (dormente).** Construída 36/38 e fechada
  como não-aplicável (começa do zero). Só reabrir se surgir uma fonte de dados a importar —
  aí 8.6/8.7 rodam o corte pelo runbook `backend/docs/runbooks/legacy-cutover.md`. Não peça
  o `RoboTrack_Database.json`: não existe e não vai existir.

**SEAMS/handoffs abertos que valem lembrar:**
- **offline-pwa:** flipar `useRecordAdvance`/`useHierarchy` para ENFILEIRAR quando
  offline + retirar o `setQueryData` (a máquina — fila/drenagem/overlay/indicador —
  está pronta e provada; falta a última fiação dos hooks de mutação). É uma mudança
  de fluxo central; merece sua própria rodada com testes.
- **delivery-and-observability:** smokes de deploy (docker-compose staging, CDN,
  Sentry real, ensaio de rollback em staging) — artefatos entregues, execução é do
  primeiro deploy real. Ver FECHAMENTO no EXECUCAO da change.
- **Branches remotas antigas** (~19) prontas para apagar; o `git push --delete` está
  bloqueado pela política de permissão (apagar pela UI do GitHub ou liberar a
  permissão).

**Convenções vigentes (não regredir ao montar mais telas):** leituras via hooks em
`features/<dominio>/` com a factory `qk.*` (o guard reprova key fora de
`['ws', wsId, …]`); telas em `app/` NÃO importam `lib/api` direto (DTOs reexportados
pela feature); mutations invalidam a chave ESPECÍFICA, nunca o tenant inteiro;
`createPortal` só em `components/menu/`; `new Notification(` só no hook de alerta do
SO (regra de lint); storage só por `lib/safeStorage` (regra de lint).

## Método (não abrir mão)

1. Uma change por vez, na branch de trabalho, **fast-forwarded para `main` a cada
   grupo** (`main` é a versão mais atual — não há mais empilhamento de branches).
2. **Antes de qualquer código**, escrever `openspec/changes/<change>/EXECUCAO.md`
   RECONCILIANDO o design com a REALIDADE do repo (o que já existe/evoluiu, o que é
   handoff), com o mapa de grupos, decisões e armadilhas previstas — commit `G0`.
3. Executar grupo a grupo. Por grupo: aplicar → specs dirigidos (0 falhas) → marcar
   `- [x]` em `tasks.md` → `npx --yes @fission-ai/openspec@1.6.0 validate <change>
   --strict` → **ATUALIZAR A DOCUMENTAÇÃO** → **um commit** `G<n>: ...` → ff `main`
   + push.
3.1 **Documentação é parte do push, não um passo posterior.** Antes de empurrar,
   verifique se a mudança tornou falso algo que um documento afirma, e conserte no
   mesmo empurrão. A tabela de "o que mudou → o que atualizar" está em `CLAUDE.md`.
   Um runbook que manda clicar num botão que não existe mais custa uma rodada do
   par. Ao remover/renomear um controle: `grep -rn "<rótulo>" *.md`.
4. Ao fim de cada grupo: resumo pt-BR client-friendly (cliente não-expert). Em lotes
   autorizados ("vai até G4"), seguir sem pausar; senão, pedir autorização.
5. Divergência entre o design e a realidade (ou entre duas changes): decidir, **registrar
   a decisão com o motivo** no EXECUCAO.md e anotar no `tasks.md`. Nunca em silêncio.
6. `pending` sempre nomeia a capacidade bloqueadora; nada de spec pendente fingindo
   cobertura de código que não existe.

## Regras que não podem regredir

- A aplicação conecta ao Postgres como `robotrack_app` — **sem SUPERUSER e sem
  BYPASSRLS** (inclusive nos seeds).
- Isolamento entre workspaces é **Row Level Security forçada**, não convenção de código.
- As invariantes moram no banco (trigger, constraint, índice único), não só no model.
- Vazamento entre tenants responde **404**, nunca 403 — corpo byte-idêntico ao de um id
  inexistente.
- As varreduras (autenticação, tenant, route-sweep de policy, cross-tenant) **só crescem**:
  rota nova nasce declarando policy e entrando no gerador cross-tenant no mesmo grupo.
- O repositório legado `mizakoreia/RoboTrack` é **somente referência de leitura** — nenhum
  arquivo dele entra neste repositório.

## Ambiente de desenvolvimento

Migrations rodam como `robotrack_migrator`; a suíte roda como `robotrack_app` (default do
`database.yml`, que já usa `DATABASE_URL` em todos os ambientes). Detalhes em
[backend/db/PROVISIONING.md](backend/db/PROVISIONING.md):

```bash
# Postgres cai com frequência — reinicie quando "Connection refused":
pg_ctlcluster 16 main start

export PATH="/opt/rbenv/versions/3.2.3/bin:$PATH"   # ruby 3.2.3 (o 3.3 sombreia)
cd backend
MIG_DEV="postgres://robotrack_migrator:mig_dev_pw@localhost/robotrack_dev"
MIG_TEST="postgres://robotrack_migrator:mig_dev_pw@localhost/robotrack_test"
RAILS_ENV=development DATABASE_URL=$MIG_DEV  bundle exec rails db:migrate
RAILS_ENV=test        DATABASE_URL=$MIG_TEST bundle exec rails db:migrate
redis-server --daemonize yes    # NECESSÁRIO para a suíte cheia (cable tickets)
RAILS_ENV=test bundle exec rspec              # a suíte INTEIRA roda (1382/0); ou dirija por capacidade

cd ../frontend
npm run lint && npx tsc --noEmit && npx vitest run    # frontend usa NPM; suíte inteira 555/0 (e2e/** roda sob Playwright, fora do vitest)
npm run typecheck:test-imports                # guarda de import em teste (q&a 1.3)
```

Para VER a GUI de verdade: `RAILS_ENV=development rails s -p 3000` + `npm run dev`
(vite :5173, proxy `/api`→:3000) e dirija o Chromium real via `playwright-core`
(`executablePath: /opt/pw-browsers/chromium-*/chrome-linux/chrome`) — foi assim que os
screenshots das telas foram feitos. Screenshot rápido de HTML solto também dá por
`chromium_headless_shell-*/chrome-linux/headless_shell --screenshot`. Validação de spec
OpenSpec: `npx --yes @fission-ai/openspec@1.6.0 validate <change> --strict`.

## PROMPT DE RETOMADA

> Estou continuando o desenvolvimento do RoboTrack (github.com/mizakoreia/robotrack_V1):
> reimplementação de um sistema legado (PWA + Firestore) sobre um template Rails 8
> API-only + React 18/TS, organizada com OpenSpec — 29 changes em `openspec/changes/`
> (as 25 do núcleo + `invite-by-code` + `join-workspace-by-code` + `code-only-invites` +
> `owner-only-card-delete`, todas já em `main`).
>
> Leia, em ordem: **`CLAUDE.md`** (regras de trabalho — inclui "documentação ANTES de
> cada push"), `CONTINUIDADE.md` (estado, modelo de git, método), e, se for tocar em
> UI, `PRODUCT.md` + `DESIGN.md` (o skill `impeccable` os lê antes de qualquer
> comando). **AS 25 changes estão COMPLETAS** — todo o backend do
> núcleo, a base visual, a moldura, as telas, a auditoria imutável, o **tempo real**
> (ActionCable), a **fila offline** (PWA), a **infra/observabilidade**, as
> **notificações** e a **migração legada** (esta última construída 36/38 e FECHADA COMO
> DORMENTE — o sistema começa do zero, sem dado a migrar; código isolado em `Legacy::*`,
> não roda). A última, `quality-and-accessibility`, FECHOU **39/39**: o **harness E2E
> (G6)** já era verde (smoke 4/4 em Chromium+WebKit) e os deltas de navegador
> (4.4/5.5/5.6/7.1-7.7/8.5) foram escritos com **`e2e:lint` verde**, a EXECUÇÃO em
> Chromium/WebKit/CI ficando como handoff documentado (§6d-§6g do `VALIDACAO_WSL.md`).
> Antes vieram `invite-by-code` (código curto de convite) e `join-workspace-by-code`
> (entrar noutro workspace por código estando logado), ambas COMPLETAS e já em `main`.
>
> **O deploy foi validado de ponta a ponta** com um par na WSL (Docker + navegador
> real): 12 bugs que só aparecem no processo REAL de produção + uma rodada de UI/UX com
> mais 9 achados de primeiro-uso. Ver as seções "Campanha de deploy" e "Rodada de
> UI/UX" no `CONTINUIDADE.md` — e os PADRÕES nomeados lá (fiação faltante ao shell,
> locator por substring, teste que passa por acaso) valem para o que vem.
>
> **O toolchain RODA por completo neste ambiente** (correção sobre notas antigas): ruby
> 3.2.3 em `/opt/rbenv` COM gems, suíte backend ~**1438** (era 1382 + ~56 da migração
> legada; `spec/legacy` 53/0 verificado — a suíte INTEIRA não foi re-rodada na última
> sessão por Postgres instável), frontend **555/0**, e Chromium+Playwright dirigem o
> browser real. O que ainda é handoff: **pipeline de CI** (WebKit já roda na WSL do par,
> e os smokes de deploy Docker foram executados e estão verdes).
>
> **Nenhuma change aberta.** `quality-and-accessibility` fechou **39/39** — os deltas
> de navegador (G-B1..G-B4: teclado, auditor de toque, axe, os 5 fluxos, INP) têm spec
> escrito + `e2e:lint` verde; a EXECUÇÃO em navegador (Chromium/WebKit) + o **pipeline
> de CI** são o handoff residual, registrado em §6d-§6g do `VALIDACAO_WSL.md`.
> `legacy-data-migration` está DORMENTE (não-aplicável, começa do zero) — nada a fazer, não
> peça o export. **O que sobra é operação de deploy/CI, não construção.**
>
> **Método (mantido):** uma change por vez; ANTES de qualquer código escreva
> `openspec/changes/<change>/EXECUCAO.md` reconciliando o design com a REALIDADE do repo
> (muita coisa já evoluiu além do que o design assume) — commit `G0`. Depois grupo a
> grupo: aplicar → specs dirigidos 0 falhas (suba Postgres/Redis quando preciso, NUNCA
> duas suítes ao mesmo tempo) → marcar `- [x]` em `tasks.md` → `validate --strict` → UM
> commit `G<n>:` → `git checkout main && git merge --ff-only <feature> && git push -u
> origin main && git checkout <feature>` → resumo pt-BR client-friendly ao cliente
> (não-expert) → seguir. Verificações que exigem deploy real/harness ausente viram
> HANDOFF documentado (padrão da casa). Commits terminam com o rodapé
> `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>` + a linha de sessão; NÃO
> inclua o id do modelo. Assinatura de commit é impossível neste ambiente (sem chave) —
> os "Unverified" do stop-hook são esperados, sem ação.
>
> Convenções (não regredir): hooks em `features/<dominio>/` com a factory `qk.*` (guard
> reprova key fora de `['ws', wsId, …]`); telas em `app/` não importam `lib/api`;
> invalidar a chave específica; `createPortal` só em `components/menu/`; `new
> Notification(` só no hook de alerta do SO; storage só por `lib/safeStorage`. As regras
> de banco (RLS forçada como `robotrack_app` sem BYPASSRLS, invariantes em trigger/CHECK,
> vazamento cross-tenant = 404) estão na seção "Regras que não podem regredir".
