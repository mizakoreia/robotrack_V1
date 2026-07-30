# EXECUCAO — notification-preferences (G0 = planejamento)

Mapa de execução escrito ANTES de qualquer código (commit G0). Preferências de
notificação por entidade da hierarquia + os dois itens pendentes do dono. NADA foi
aplicado: sem migração, sem push, sem tocar em servidor/túnel.

## Skills aplicadas (pedido do dono)

Verificação do que existe em `.claude/skills/` deste repo: **caveman**, **frontend-design**,
**impeccable**. Resultado por skill pedida:

- **openspec** — NÃO é uma skill de arquivo; é a metodologia/CLI (`openspec/config.yaml` +
  `npx @fission-ai/openspec@1.6.0`). **Em uso**: esta change segue o esquema `spec-driven`
  (proposal/design/specs delta/tasks/EXECUCAO) e as regras pt-BR/SHALL/cenário-executável do
  `config.yaml`. Validada com `--strict`.
- **caveman** — skill EXISTE (`.claude/skills/caveman/`) e está **aplicada** ao chat (saída
  tersa; NÃO aos artefatos versionados, que seguem bem-formados). **Não tem modo/arg "ultra"**:
  é um estilo plano de economia de tokens, sem parâmetros. Reportado ao dono.
- **impeccable** — skill EXISTE e foi **carregada** (register `product`: `reference/product.md`
  + PRODUCT.md/DESIGN.md via `context.mjs`). Aplicada ao desenho de UX (D-P9): controle ≠ badge,
  alvo ≥40px de luva, `PortalMenu` com três alvos explícitos em vez de toggle que cicla, estado
  efetivo **com origem** (estado honesto), sem literal solto, sem emoji.
- **rtk** — **NÃO existe** como skill (`.claude/skills/` não a tem) e **não aparece em lugar
  nenhum do repo** (grep `\brtk\b` em `.md/.json/.yaml/.ts/.tsx/.rb` → 0 ocorrências). O
  significado usual de "RTK" em React/TS é **Redux Toolkit** (biblioteca de estado). O projeto
  usa **Zustand + TanStack React Query** por decisão de arquitetura (`config.yaml`). **Não
  introduzi Redux Toolkit** — aguardo confirmação do dono sobre o que "rtk" designa antes de
  qualquer coisa nessa direção.

## RECONCILIAÇÃO COM A REALIDADE (crítico — ler antes de codar)

- **Pipeline existente** (`in-app-notifications`, COMPLETO): o disparo é por
  `ActiveSupport::Notifications.instrument(...)` **pós-commit** (não `after_commit` de model);
  subscribers em `config/initializers/notification_subscribers.rb` enfileiram `NotifyTaskEventJob`
  (fila `:notifications`, `retry: 5`, 1º arg = `workspace_id` para o middleware de tenant). O
  `CreateService` compõe `EventClassifier` + `RecipientResolver` + `with_owner` + `MessageBuilder`
  e insere via savepoint (`requires_new: true`, tolera o índice único de idempotência).
- **Ponto de filtro:** `CreateService#insert_for` já resolve o `ctx`
  (`project_id`/`cell_id`/`robot_id`/`task_id` subindo task→robot→cell). É **ali** que o filtro
  de preferências entra (D-P4) — o `RecipientResolver` segue puro.
- **Owner:** `Workspace.owner_user_id` → `Person.find_by(user_id:)` (`owner_person_id`). A
  EXTENSÃO já faz o dono receber avanços; com preferências vira o DEFAULT do dono (D-P10).
- **Idioma de RLS (exato, das demais tabelas):**
  `ENABLE`/`FORCE ROW LEVEL SECURITY` + `CREATE POLICY tenant_isolation ... USING/WITH CHECK
  (workspace_id = NULLIF(current_setting('app.current_workspace_id', true), '')::uuid)`.
- **FK composta:** `people` tem único `(workspace_id, id)`; `projects`/`cells`/`robots` têm
  `UNIQUE (id, workspace_id)` (`uq_<tbl>_id_workspace`). Padrão de `task_assignees`.
- **Migração:** `ActiveRecord::Migration[8.0]`, SQL cru, `schema_format = :sql` (`db/structure.sql`,
  não `schema.rb`). GRANT ao `robotrack_app` **automático** por default-privileges do
  `robotrack_migrator` (`db/roles.sql`) — tabela nova não precisa de GRANT explícito. Timestamp
  `20260726NNNNNN`. Migrations rodam como `robotrack_migrator`.
- **NotificationPolicy** existente é referência de idioma para a nova
  `NotificationSubscriptionPolicy` ("própria" por policy, não banco).
- **PermissionMatrix** é dado (`ACTIONS = {...}`); nova action `manage_own_subscription` entra na
  matriz **e** no spec que a reafirma literalmente.
- **Frontend:** `useNotifications` (key `qk.notifications`, contagem derivada, invalidate no
  `onSuccess`) é o molde de `useNotificationSubscriptions`. `qk.subscriptions` entra em
  `lib/query/keys.ts` (guarda de forma de key exige prefixo `['ws', tenant, …]`). Sprite só tem
  `bell` — `bell-off` a adicionar. Strings do centro estão inline hoje — esta change cria
  `src/lib/i18n/notifications.ts` canônico.
- **Postgres cai com frequência** no ambiente (`pg_ctlcluster 16 main start`); Redis necessário
  para a suíte cheia.

## Ordem dos grupos (mapa) — 🔴 = migração com reversão NÃO-trivial

| Grupo | Escopo | Banco |
|---|---|---|
| **G0** | Planejamento/reconciliação + materialização da change (este doc) | 🟢 |
| **G1** | Tabela `notification_subscriptions`: enum de estado, FKs compostas, CHECK um-alvo, RLS forçada, índices únicos parciais + lookup, model, spec SQL cru | 🟡 migração aditiva (reverte por `DROP`) |
| **G2** | `SubscriptionResolver` (mais-específico-vence, 1 query) + filtro em `CreateService#insert_for`; specs de tabela e integração | 🟢 |
| **G3** | API pessoal (`GET`/`PUT` upsert, `default` apaga) + `manage_own_subscription` na matriz + `NotificationSubscriptionPolicy` + route-sweep + negações | 🟢 |
| **G4** | UX: `bell-off` no sprite, `i18n/notifications.ts`, `useNotificationSubscriptions`, `NotificationPreferenceControl` nos cabeçalhos robô/célula/projeto; teste de componente | 🟢 |
| **G5** | Item pendente 1 — `assign_observer` (3ª pessoa, `type='assign'`), dono/seguidores observadores, `msg` por destinatário; specs | 🟢 (sem enum) |
| **G6** | Item pendente 2 — `ALTER TYPE ... ADD VALUE 'structure'`, locale estrutural, `structure.changed` pós-commit (create/delete), `NotifyStructureEventJob`, recipientes dono+seguidores−autor honrando mute; specs | 🔴 **migração; reversão NÃO-trivial** |
| **G7** | Suíte completa + docs (`CONTINUIDADE`, EXTENSÃO fechada) + `validate --strict` | 🟢 |

**Só G1 e G6 tocam o banco.** G1 é aditivo e reverte por `DROP TABLE`/`DROP TYPE`. **G6 é o
único ponto onde o `down` não é trivial** (`ALTER TYPE ADD VALUE` não tem `DROP VALUE`; reverter
exige recriar `notification_type` e recompor as colunas que o usam).

## Armadilhas previstas

- **Ordem sagrada do pipeline:** o filtro entra DEPOIS de candidatos∪seguidores e ANTES da
  subtração do autor (D-P4). Inverter deixaria um seguidor-autor se auto-notificar.
- **Herança:** mais-específico-vence tem que checar robô→célula→projeto **nessa** ordem; um
  `mute` de projeto NÃO pode vencer um `follow` de robô.
- **`ALTER TYPE ADD VALUE`** precisa de `disable_ddl_transaction!` (não roda em transação que já
  usa o valor). Reversão marcada `IrreversibleMigration`.
- **assign observador materializado por destinatário:** hoje `insert_for` constrói `msg` UMA vez;
  para 2ª/3ª pessoa por destinatário, o caso `assign` passa a construir por destinatário. Não
  quebrar a idempotência (`type='assign'` mantido).
- **Invariante 4 vizinha:** a preferência amplia a escrita do `view`; self-scoped + RLS + policy
  de "própria linha". Decisão O-5 pede OK do dono.
- **Sweeps do frontend:** `query-convention` (key nova), `no-emoji` (o `bell-off`), literal solto
  (i18n). Todos previstos em G4.

## Decisões em aberto (para o dono) — ver design.md §Perguntas

O-1 default · O-2 herança · O-3 owner-tudo×mute · O-4 assign×mute · O-5 view calibra ·
O-6 item 1 sem enum · O-7 alvo workspace · O-8 quais ações estruturais. Cada uma com recomendação
no `design.md`.

## EXECUÇÃO por grupo (parte reversível — G6 DEFERIDO)

- **G1 ✅** — enum `notification_subscription_state`, tabela `notification_subscriptions` (FKs
  compostas, CHECK um-alvo, RLS forçada, 3 únicos parciais + 3 lookup), model
  `NotificationSubscription` (`WorkspaceScoped`, validação uma-de-três). Migração aplicada em DEV
  **e** TEST como `robotrack_migrator`; `structure.sql` regenerado. Spec `spec/db/
  notification_subscriptions_schema_spec.rb` **9/0** (CHECK, enum, FK cross-ws, único, CASCADE, RLS).
- **G2+G5 ✅** (acoplados no `create_service.rb`) — `SubscriptionResolver` (puro, 1 query,
  mais-específico-vence). `CreateService#for_advance` filtra candidatos (seguidor entra, silenciador
  sai, dono-mute sobrepõe owner-tudo). `for_assign` ganha observadores em 3ª pessoa
  (`assign_observer`, `type='assign'`, SEM migração de enum; atribuído segue 2ª pessoa e isento de
  mute — O-4). `MessageBuilder` aceita `assignee:`. Locale `assign_observer` adicionado; grep-guard
  estendido para `à tarefa "`. Specs: `subscription_filter_spec.rb` 13/0; suíte de notificações
  inteira **52/0** (sem regressão da notificação-do-dono nem das invariantes 4/8).
- **G3 ✅** — action `manage_own_subscription` na `PermissionMatrix` (owner/edit/view) +
  reafirmação nos specs `permission_matrix_spec` e `matrix_conformance_spec` (24→27 células).
  `NotificationSubscriptionPolicy` (matriz primeiro, fail-closed p/ papel nulo; posse por simetria
  com `mark_read?`). Controller `Api::V1::NotificationSubscriptions` (`GET` lista as próprias; `PUT`
  upsert por `scope_type`/`scope_id`/`state`; `default` apaga) — **não aceita `person_id`**, então
  editar a alheia é impossível por construção. Entity `NotificationSubscription`. Montado no `base.rb`.
  Specs: request `notification_subscriptions_spec` (upsert idempotente, default apaga, view gere a
  própria, GET só as próprias, não-membro barrado). Suíte autorização/tenancy/policy **294/0** (7
  pending pré-existentes); route-sweep valida a nova rota.
- **G4 ✅** (frontend) — `bell-off` no sprite (currentColor, sem emoji); `qk.subscriptions`;
  `notificationSubscriptionsApi` (endpoints); `i18n/notifications.ts` (rótulos, sem literal solto).
  Hook `useNotificationSubscriptions` (query key `['ws',wsId,'subscriptions']`, upsert OTIMISTA,
  `resolveEffective` mais-específico-vence + origem). Componente `NotificationPreferenceControl`
  (`IconButton` sino → `PortalMenu` Padrão/Seguir/Silenciar, ≥40px, teclado, estado efetivo com
  origem) montado nos cabeçalhos de `RobotTaskTablePage`/`CellPage`/`ProjectPage`. `DESIGN.md`
  atualizado. Specs: `NotificationPreferenceControl.test` 6/0; sweeps (query-convention, no-emoji,
  convention, contrast) verdes; `tsc`/`lint` limpos; suíte frontend **618/619** (a única falha é o
  flaky pré-existente `queue.test.ts` D7-12, que passa isolado — domínio offline, intocado).
  **Limitação v1 registrada:** na tela do robô a ancestralidade exibida é robô→célula (o
  `project_id` não vem no header do robô); um `mute` de PROJETO ainda é honrado pelo servidor, mas
  não aparece como estado herdado no sino do robô. Sem impacto no comportamento das notificações.
- **G6 ⏸️ DEFERIDO** — eventos estruturais + `ALTER TYPE ADD VALUE 'structure'` NÃO executado
  (reversão não-trivial); aguardando OK separado do dono. tasks.md §6 marcado.

## Baseline

`in-app-notifications` COMPLETO e verde. `notification_subscriptions` não existe. Frontend com
`useNotifications`/`NotificationBell`/`NotificationCenter` prontos. NADA desta change aplicado —
G0 é só planejamento.

## RETOMADA

Ler este arquivo + `design.md` (D-P1…D-P10 + §Plano de migração + §Perguntas em aberto). Antes de
G1, obter OK do dono para a **migração exata** (design.md §Plano) e para as decisões O-1..O-8.
Protocolo por grupo: aplicar → specs dirigidos 0 falhas (subir Postgres/Redis) → marcar `tasks.md`
→ `validate --strict` → atualizar docs → UM commit `G<n>:` → ff `main` + push → resumo pt-BR.
Migrations como `robotrack_migrator`. NÃO commitar os arquivos de túnel (`frontend/vite.config.ts`,
`frontend/src/lib/api/client.ts`).
