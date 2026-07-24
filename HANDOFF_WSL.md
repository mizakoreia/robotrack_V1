# Handoff — deploy do RoboTrack a partir da WSL

Prompt de partida para o próximo agente. A WSL é o ambiente com Docker + navegador real
(Chromium **e WebKit**) que o container de desenvolvimento não tem — é ela que fecha os
handoffs de entrega e os testes E2E de navegador.

---

Você vai fazer o deploy do RoboTrack a partir da WSL (github.com/mizakoreia/robotrack_v1).

**Antes de qualquer coisa, leia dois arquivos na raiz:**
- `CONTINUIDADE.md` — estado atual, modelo de git, o que já foi entregue, o método e as
  regras que não podem regredir.
- `VALIDACAO_WSL.md` — **o seu runbook.** Tem o setup da WSL (§2), a checagem de paridade
  (§3) e, o principal pra você, os HANDOFFS que só a WSL valida (§4) e o que nem a WSL
  fecha (§5).

**Estado (não re-descobrir):** `main` é a versão mais atual (`git fetch origin main` → tip
`9621e41`). **24 de 25 changes COMPLETAS.** Suítes verdes no container: **backend 1443/0**
(9 pending esperados), **frontend 539/0**, `tsc`/`eslint`/guarda-de-imports limpos.
`legacy-data-migration` está **DORMENTE/não-aplicável** (o sistema começa do zero, sem dado
a migrar) — **não toque nela e não peça o `RoboTrack_Database.json`; não existe.**

**Passo 0 — sanidade da WSL:** rode a paridade do `VALIDACAO_WSL.md §3`
(`RAILS_ENV=test bundle exec rspec` → esperado **1443/0, 9 pending**; `npx vitest run` →
**539/0**). Se divergir do container, o problema é a WSL, não o código — conserte o
ambiente antes de seguir.

**Seu trabalho tem duas frentes (a WSL desbloqueia ambas):**

### A) Deploy / smokes de entrega
Os handoffs de `delivery-and-observability` (código+config+spec entregues; a execução REAL
é o deploy). Do `VALIDACAO_WSL.md`:
- **§4.1** — build da imagem de produção backend + **smoke da stack de staging**
  (`docker-compose`: Postgres+Redis+`bin/release`+web+worker → espera `/health/ready = 200`).
- **§4.3** — headers de cache do `nginx.conf` (imutável em assets com hash, `no-store` no
  `sw.js`/HTML).
- **§4.4** — guarda de topologia de Redis (o boot em produção ABORTA se cache e fila
  resolvem pro mesmo `(host,porta,db)`).
- **§4.5** — broadcast multi-processo do ActionCable (dois pumas, um publica, o outro entrega).
- **§4.2** — service worker num navegador REAL (registro network-first, offline).
- **§5** — o que **nem a WSL** fecha (CDN real, ingestão Sentry real, ensaio de rollback em
  staging na nuvem): documente como pendência, não force.

### B) `quality-and-accessibility` (a 25ª change, 25/39)
As 14 tarefas abertas são TODAS browser-gated e é a WSL que as viabiliza: harness
`@playwright/test` (Chromium **+ WebKit**, build de produção servido) [6.1-6.3], os 5 fluxos
E2E [7.1-7.7], gate `@axe-core/playwright` [5.6], E2E só-teclado [4.4], auditor de alvo de
toque [5.5], INP com 24 cards [8.5]. A lógica já tem cobertura de integração RTL; aqui é a
versão de browser real. **Se for construir isto: comece pelo `EXECUCAO.md` da change**
(reconcilie o que já existe vs o delta) e siga grupo a grupo.

**Método (mantido, não abrir mão):**
1. Trabalhe na branch `claude/robotrack-task-catalog-tc-g3-6os4vm` (crie de `origin/main`
   se não existir).
2. Para a frente B (implementação): **ANTES de código**, leia
   `openspec/changes/quality-and-accessibility/EXECUCAO.md` (a onda já foi começada — o G0
   existe). Grupo a grupo: aplicar → specs 0 falhas → `- [x]` no `tasks.md` →
   `npx --yes @fission-ai/openspec@1.6.0 validate quality-and-accessibility --strict` → UM
   commit `G<n>:` → `git checkout main && git merge --ff-only <branch> && git push -u origin
   main && git checkout <branch>` → resumo pt-BR client-friendly.
3. Para a frente A (deploy): cada smoke que passar, marque a tarefa correspondente e
   registre o resultado no `EXECUCAO.md` de `delivery-and-observability` (seção FECHAMENTO).
   O que exigir nuvem real vira HANDOFF documentado — padrão da casa.
4. Divergência design × realidade: **decida, registre o motivo** no `EXECUCAO.md` e anote no
   `tasks.md`. Nunca em silêncio.
5. Commits terminam com o rodapé `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>` +
   a linha de sessão. NÃO inclua o id do modelo em nenhum artefato.

**Regras de banco que não regridem:** a app conecta como `robotrack_app` (SEM
SUPERUSER/BYPASSRLS); isolamento entre workspaces é RLS forçada; invariantes moram no banco
(trigger/CHECK/índice); vazamento cross-tenant responde **404** (corpo byte-idêntico a id
inexistente). Migrations como `robotrack_migrator`; a suíte como `robotrack_app`.

Ao terminar (ou travar), devolva: o que passou, o que falhou com a saída exata, e o que
virou handoff de nuvem. Não deixe teste sem rodar fingindo cobertura.
