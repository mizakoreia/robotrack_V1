# EXECUCAO — commissioning-hierarchy

Mapa de execução das 32 tarefas de `tasks.md`, em grupos coerentes, um commit
por grupo. Mesmo método das cinco changes anteriores (ver os `EXECUCAO.md`
delas; o desta onda anterior é `authorization-policies/EXECUCAO.md`).

Escrito ANTES de qualquer código. Sessão caiu → seção **RETOMADA** no fim.

## Ponto de partida

- Branch: `commissioning-hierarchy`, criada de `authorization-policies`
  (`6b89283` — main local NÃO tem as ondas 5+; o empilhamento é o padrão).
  **Sem push.**
- Baseline (21/07/2026, backend como `robotrack_app`): **backend 464 / 0
  (9 pending deliberados)**, **frontend 63 / 0**, `tsc --noEmit` limpo.
- Ambiente WSL desta máquina (ver EXECUCAO de authorization-policies, "Ponto de
  partida"): migrations como `robotrack_migrator`, suíte como `robotrack_app`,
  frontend com pnpm. Postgres precisa de `service postgresql start`.
- `pgcrypto`/`citext` JÁ habilitadas (donas: `robotrack_migrator`) — a migration
  1.1 vira `enable_extension` idempotente (no-op aqui, real em ambiente novo).
- **As policies ProjectPolicy/CellPolicy/RobotPolicy JÁ EXISTEM** (singleton,
  criadas no G1 de authorization-policies, mapeando §4.1). A tarefa 4.6 vira
  verificação/ajuste (ex.: conferir `reorder?`/`assign?`), não criação.
- O gate exige `route_setting :policy` em TODA rota nova (route-sweep da
  superfície inteira) e a varredura cross-tenant exige gerador ou override por
  rota com `:id` — os endpoints novos NASCEM sob as duas varreduras.

## O objetivo central desta change

O esqueleto do domínio: `projects → cells → robots` como tabelas relacionais
com tenancy no BANCO (FK composta + RLS forçada), PK `uuid` gerável no cliente
(D1/D13 — pré-condição do offline), `position` única/contígua/0-based (§2.9) e
`progress_cache` desde a origem (D5). Primeiro nó do caminho crítico da Onda 3.

## Mapa de grupos

| Grupo | Área | Tarefas | Depende |
|---|---|---|---|
| **G0** | Este mapa | — | baseline |
| **G1** | Esquema: 4 migrations (+pgcrypto), RLS, spec de esquema | 1.1–1.6 | baseline |
| **G2** | Models + concerns (WorkspaceScoped/PositionScoped) + identidade do cliente (IdValidator, IdempotentCreate) | 2.1–2.4, 3.1–3.3 | G1 |
| **G3** | Services, entities, endpoints CRUD, policies (verificação), suíte negativa | 4.1–4.7 | G2 |
| **G4** | Reordenação em lote (ReorderService, endpoints, 409 por conjunto, concorrência) | 5.1–5.4 | G3 |
| **G5** | Cliente: endpoints.ts, newId(), hooks React Query, mutations otimistas, handler de d&d, testes | 6.1–6.6 | G4 |
| **G6** | Fechamento: seed 2×(3 proj/6 cél/12 robôs), spec de contrato de FK com robot-tasks, conferência final | 7.1–7.2 | G5 |

Total: 32 tarefas em 6 grupos. Sequencial.

## Decisões de desenho já fixadas (não reabrir)

- **D-H1** PK `uuid` default `gen_random_uuid()`, id aceito do cliente com
  regex v1–v8 RFC 4122; UUID nulo → 422 com mensagem própria.
- **D-H2** replay idêntico → 200; colisão divergente → 409 com recurso atual;
  id de outro tenant → 404 byte-idêntico a inexistente (via RLS, não checagem).
- **D-H3** `position` inteira contígua 0-based por escopo; índice único
  `(escopo, position) DEFERRABLE INITIALLY DEFERRED`; novo item = MAX+1 sob
  lock do pai.
- **D-H4** reorder em lote `{scope_id, ordered_ids}`; conjunto divergente →
  409 com conjunto atual, sem escrita; `FOR UPDATE` no pai; `lock_version` NÃO
  participa da reordenação.
- **D-H5** `workspace_id` desnormalizado NOT NULL + `UNIQUE (id, workspace_id)`
  + FK composta filho→pai `ON DELETE CASCADE` + RLS `FORCE` com
  `tenant_isolation`.
- **D-H6** exclusão física cascateada por FK; auditoria na MESMA transação do
  DELETE (falhou auditoria → não exclui); audit_logs/notifications NÃO
  cascateiam; `updated_by_person_id` é `ON DELETE SET NULL`.
- **D-H7** `progress_cache jsonb NOT NULL DEFAULT '{}'` + `progress_cached_at`
  nas 3 tabelas; a SEMÂNTICA é de progress-rollup.
- **D-H8** nome único por escopo case-insensitive (`(escopo, lower(name))`) +
  `CHECK (length(btrim(name)) BETWEEN 1 AND 120)`.
- **D-H9** `lock_version` nos 3 níveis; 409 com recurso atual; rollup e reorder
  não tocam nele.
- **D-H10** `application` como `text` + CHECK dos 6 literais pt-BR da §1.2;
  default `'Misto / Geral'`.
- **D-H11** leitura tolerante no SERVIDOR: coleções sempre `[]`, cache vazio →
  `{weighted: 0, done: 0, total: 0}`.

## Decisões que EU tomo aqui

1. **Policies existentes são reaproveitadas** (ver Ponto de partida). O que o
   G3 adiciona: os endpoints DECLARAM `{ policy:, action: }` e a suíte de
   request negativa exercita 403/404/409 por HTTP. Nenhuma policy nova.
2. **Auditoria (4.1) sem tabela `audit_logs`** (é de `audit-log`): a entrada de
   auditoria da exclusão NESTA change segue o precedente de
   `membership_revocations` — NÃO crio a tabela da outra change; registro a
   exclusão via `Rails.logger` estruturado (evento `hierarchy_destroy`) dentro
   da transação E deixo o gancho de service isolado num método único
   (`audit_destroy!`) que `audit-log` troca pela escrita na tabela. A
   invariante "auditoria falhou → não exclui" fica adiada com o pending
   correspondente — um logger não falha de forma útil. Registrado como
   pendência para `audit-log`.
3. **Varreduras de conformidade crescem NESTE grupo, não depois**: cada rota
   nova com `:id` ganha entrada no GERADORES do `cross_tenant_spec` no MESMO
   grupo do endpoint (G3/G4); o route-sweep já cobra a declaração sozinho. O
   pending "manage_commissioning por HTTP" da matriz (5.5 da change anterior)
   é REMOVIDO no G3 — os cenários viram testes reais. O pending de
   `record_progress` é PARCIALMENTE resolvido no G4 (reordenação é da linha
   §4.1 L3); o restante (avanço, atribuição) continua pending por
   `progress-advances`/`robot-tasks`.
4. **`schema_guard_spec` da Onda 1** exige das tabelas novas: `workspace_id
   NOT NULL`, índice começando por `workspace_id`, FORCE RLS e policy
   `tenant_isolation`. As migrations do G1 nascem conformes — conferir o guard
   ANTES de escrever o spec 1.6 para não duplicar asserções.
5. **G5 (cliente) sem tela**: `hierarchy-screens` é outra change. Hooks,
   mutations otimistas e handler de d&d entram como módulos testados por
   Vitest (o handler é função pura + hook, plugável na tela futura). Nenhuma
   rota/página nova no router.
6. **Seed (7.1) roda como `robotrack_app` sob `Tenant.with`** por workspace —
   seed que precisasse de BYPASSRLS seria regressão. Dois workspaces com
   projetos de MESMO nome e ids adjacentes (vazamento visível a olho nu).
7. **`reorder` de projects tem escopo = workspace**: `scope_id` do corpo é
   redundante com o contexto — exigido igual ao `X-Workspace-Id` (coerência
   D-H4), divergência → 422. Para cells/robots, `scope_id` é o pai real.

## Armadilhas previstas

1. **Índice único DEFERRABLE não sai em `add_index` do Rails** — precisa de
   SQL (`execute`) na migration; `structure.sql` capta. Conferir que o
   `DEFERRABLE INITIALLY DEFERRED` aparece no dump.
2. **`FOR UPDATE` no pai de projects é a linha do WORKSPACE** — que tem RLS
   forçada e política de UPDATE restrita (`roles.sql` revogou UPDATE de coluna;
   `SELECT ... FOR UPDATE` exige privilégio de UPDATE na TABELA). O
   `robotrack_app` NÃO tem UPDATE de tabela em `workspaces` (só colunas
   name/updated_at) — `FOR UPDATE` pode falhar com permission denied. Testar
   cedo no G2 (PositionScoped); fallback: advisory lock
   (`pg_advisory_xact_lock(hashtext(workspace_id))`) para o escopo de projects,
   `FOR UPDATE` normal para cells/robots.
3. **RLS + `ON CONFLICT (id) DO NOTHING`**: id existente em OUTRO tenant não é
   visível ao SELECT, mas o INSERT colide na PK global e a política WITH CHECK
   não deixa distinguir — a violação de PK chega como exceção. Traduzir
   `RecordNotUnique`→busca→404 conforme D-H2, e testar o corpo byte-idêntico.
4. **`tenant_route_sweep_spec` (Onda 1)**: as rotas novas são de DOMÍNIO — têm
   de responder `400 workspace_context_missing` sem header. Não entram em
   isenção nenhuma.
5. **Truncation vs transação**: specs de concorrência da reordenação (5.4) com
   threads exigem tag `:tenancy` e dados fora da transação do exemplo (mesma
   armadilha 5 de workspace-invitations).
6. **Entities Grape: uma classe por arquivo** (Zeitwerk — precedente da onda 4).
7. **`updated_by_person_id`**: `Person` do autor pode não existir (usuário via
   convite tem; dono tem pela bootstrap; mas não assumir) — resolver via
   `context.person` do gate; `nil` permitido (coluna nullable, SET NULL).
8. **Vite/dev servers**: se o backend de dev estiver rodando durante
   migrations, reiniciar depois (schema cache).

## Protocolo por grupo

1. Aplicar tarefas (migrations como `migrator`, dev E test).
2. `bundle exec rspec`; G5/G6 também `vitest run` + `tsc --noEmit`.
3. Marcar `- [x]` em `tasks.md`.
4. `npx --yes @fission-ai/openspec@1.6.0 validate commissioning-hierarchy --strict`.
5. Commit `G<n>:`. Sem push. Nada de `.env`/coverage no commit.

## Estado esperado da suíte por grupo

| Após | Backend |
|---|---|
| Baseline | 464 / 0 (9 pending) |
| G1 | + spec de esquema (information_schema/pg_class) verde |
| G2 | + specs de model, concerns e idempotência |
| G3 | + suíte negativa de CRUD; pending "manage_commissioning por HTTP" REMOVIDO (vira teste real); cross-tenant GERADORES += 6+ rotas |
| G4 | + specs de reorder (conjunto, concorrência, lock_version intocado); pending de record_progress reduzido a avanço/atribuição |
| G5 | backend inalterado; frontend 63 → ~70+ |
| G6 | + seed + spec de contrato de FK (pending por robot-tasks) |
| Alvo | 0 falhas; pendings só com dono nomeado |

## Progresso

- [ ] G1 — Esquema (1.1–1.6)
- [ ] G2 — Models + identidade (2.1–2.4, 3.1–3.3)
- [ ] G3 — CRUD (4.1–4.7)
- [ ] G4 — Reordenação (5.1–5.4)
- [ ] G5 — Cliente (6.1–6.6)
- [ ] G6 — Fechamento (7.1–7.2)

## RETOMADA

1. `git log --oneline -8` na branch `commissioning-hierarchy` — um commit por
   grupo, prefixo `G<n>:`; o próximo é o seguinte da tabela.
2. `tasks.md` tem o estado fino; `- [x]` sem commit = sessão caiu no meio.
3. Baseline antes de codar: migrations como `robotrack_migrator` (dev e test),
   `bundle exec rspec` (0 falhas), `vitest run` + `tsc` no frontend (pnpm).
4. Reler **Decisões que EU tomo** e **Armadilhas** — em especial a 2 (FOR
   UPDATE em workspaces sem privilégio) e a 3 (ON CONFLICT sob RLS).
5. Invioláveis: sem push, sem `.env` em commit, runtime sem
   SUPERUSER/BYPASSRLS, RLS forçada nas tabelas novas, varreduras só crescem,
   cross-tenant = 404 byte-a-byte.
6. Seis grupos `- [x]` → atualizar Progresso, escrever CONCLUSÃO, parar.
