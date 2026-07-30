> **Legenda de risco de banco:** 🟢 sem migração · 🟡 migração aditiva reversível por `DROP`
> · 🔴 migração com reversão **NÃO-trivial** (ponto onde o dono precisa saber que o `down`
> não é um `DROP` simples).

## 0. Planejamento (G0) 🟢

- [x] 0.1 Reconciliar design × realidade lendo `in-app-notifications` inteira (pipeline,
  invariantes 4/8, RLS, EXTENSÃO), confirmar idioma de RLS/FK composta e o ponto de filtro no
  pipeline, e materializar esta change (proposal/design/specs/tasks/EXECUCAO). (Método da casa —
  `validate --strict` verde antes de qualquer código)

## 1. Esquema `notification_subscriptions` (G1) 🟡 — MIGRAÇÃO

- [x] 1.1 Criar o enum `notification_subscription_state` (`follow`, `mute`) e a tabela
  `notification_subscriptions` com as colunas de D-P1, a CHECK `chk_notif_sub_one_scope`
  (`num_nonnulls(scope_project_id, scope_cell_id, scope_robot_id) = 1`), e as FKs compostas por
  `workspace_id` (person → `people(workspace_id, id)`; project/cell/robot → `x(id, workspace_id)`).
  (§D-P1 — INSERT com dois alvos falha na CHECK; alvo de outro workspace falha na FK composta)
- [x] 1.2 Adicionar RLS **forçada** no idioma exato das demais tabelas (`ENABLE` + `FORCE` +
  policy `tenant_isolation` com `NULLIF(current_setting('app.current_workspace_id', true), '')::uuid`)
  e o índice `index_notification_subscriptions_on_workspace_id`. (§D2 — `SET app.current_workspace_id`
  do WS A e `SELECT` não retorna linha do WS B)
- [x] 1.3 Criar os três índices únicos parciais por alvo (`uq_notif_sub_person_{project,cell,robot}`)
  e os três índices de lookup do resolver (`idx_notif_sub_by_{project,cell,robot}`). (§D-P1/D-P5 —
  segunda preferência da mesma pessoa para o mesmo alvo é rejeitada; o lookup por galho usa índice)
- [x] 1.4 Model `NotificationSubscription` com `include WorkspaceScoped` (auto `workspace_id`,
  default_scope) e as associações/validações de ergonomia (uma-de-três, enum). Regenerar
  `structure.sql`. (§D-P1 — o model dá 422 legível; a garantia é o banco)
- [x] 1.5 Spec de banco por **SQL cru** exercitando 1.1–1.3 (CHECK de um-alvo, FK composta
  cross-workspace, único parcial, RLS forçada). (§D2/D-P1 — as invariantes de esquema não dependem
  do ActiveRecord)

## 2. Resolução e filtro no pipeline (G2) 🟢

- [x] 2.1 `Notifications::SubscriptionResolver` — objeto puro `wants?(person_id, ctx, default:)`
  (mais-específico-vence: robô > célula > projeto; sem linha → `default`) + carregador que traz as
  linhas do galho numa única query (D-P5). (§D-P3 — tabela-verdade dos casos: follow-em-mute,
  mute-em-follow, herança de nível, ausência → default)
- [x] 2.2 Ligar o filtro no `CreateService#insert_for` na ordem de D-P4 (candidatos ∪ seguidores →
  `uniq` → −actor → `select { wants? }`), sem tocar em `RecipientResolver` (segue puro). (§D-P4 —
  seguidor não-autor entra; silenciador responsável sai; dedup e "nunca o autor" preservados)
- [x] 2.3 Spec de tabela do resolver + spec de integração do `CreateService`: seguidor recebe,
  seguidor-autor não, silenciador responsável não, tabela vazia = comportamento de hoje, falha de
  leitura não derruba o avanço. (§D-P3/D-P4 — os cinco casos-limite; a tabela vazia é a prova de
  não-regressão)

## 3. API pessoal + autorização (G3) 🟢

- [x] 3.1 Adicionar a action `manage_own_subscription` à `PermissionMatrix` (`owner`/`edit`/`view`)
  e ao spec que reafirma a matriz literalmente. (§D-P6 — a matriz muda nos dois lugares de propósito)
- [x] 3.2 `NotificationSubscriptionPolicy < BasePolicy` exigindo `person_id == context.person.id`
  para escrever/apagar (idioma do `mark_read?`), e `GET` escopado à própria pessoa. (§D-P6 — Ana
  editando a preferência de Bruno é negada)
- [x] 3.3 Endpoints Grape `GET /api/v1/notification_subscriptions` e `PUT` (upsert; `state:'default'`
  apaga), com `route_setting :policy` e entity `Api::Entities::NotificationSubscription`; registrar
  no route-sweep de D3. (§D-P6 — upsert idempotente; voltar ao padrão apaga a linha; sweep acha a
  policy)
- [x] 3.4 Specs de request: listagem só das próprias, upsert idempotente, `default` apaga, edição
  alheia negada, isolamento cross-tenant. (§4.1 inv. 1/4 — negações obrigatórias)

## 4. UX — sino seguir/silenciar nas telas (G4) 🟢

- [ ] 4.1 Adicionar `bell-off` ao sprite (`<symbol id="i-bell-off">` + `ICON_NAMES`), sem emoji,
  currentColor; criar `src/lib/i18n/notifications.ts` com os rótulos (Padrão/Seguir/Silenciar +
  descrições + textos de origem "pelo projeto"/"pela célula"). (DESIGN.md — nenhum literal solto,
  nenhum emoji)
- [ ] 4.2 Hook `useNotificationSubscriptions` (query key `qk.subscriptions(wsId)` adicionada em
  `keys.ts`; passa no `query-convention` sweep) com upsert otimista (molde de `useDeleteRobot`),
  invalidando a chave específica; e um seletor que resolve o **estado efetivo + origem** de uma
  entidade a partir das linhas. (D9 — nenhum `useEffect + apiClient`; sem `window.location.reload`)
- [ ] 4.3 Componente `NotificationPreferenceControl` (IconButton sino → `PortalMenu` com Padrão/
  Seguir/Silenciar, alvo ≥40px, teclado, `prefers-reduced-motion`) e montá-lo nos cabeçalhos de
  `RobotTaskTablePage`, `CellPage`, `ProjectPage`. (impeccable/product — controle ≠ badge; três
  alvos explícitos, não um toggle que cicla)
- [ ] 4.4 Teste de componente: estado efetivo (próprio e herdado com origem), alternância
  otimista sem reload, e a11y (aria-label, foco, `bell-off` sem emoji). (DESIGN.md — estado honesto
  com origem; §regra de sweep de ícone/emoji)

## 5. Atribuição a terceiros — item pendente 1 (G5) 🟢

- [x] 5.1 Adicionar a chave `pt-BR.notifications.v1.assign_observer` (3ª pessoa,
  `%{author} atribuiu %{assignee} à tarefa "%{task}" (robô %{robot})`) e ensinar o `MessageBuilder`
  a renderizá-la por destinatário. (§D-P7 — a string 3ª pessoa fica no locale versionado, não inline)
- [x] 5.2 Estender o caminho `assign` do `CreateService` para incluir dono + seguidores do galho
  (menos atribuído e autor) como destinatários **observadores**, materializando a `msg` por
  destinatário (2ª pessoa ao atribuído, 3ª aos observadores), mantendo `type = 'assign'`. (§D-P7 —
  sem migração de enum; idempotência de assign preservada)
- [x] 5.3 Specs: dono recebe 3ª pessoa e atribuído recebe 2ª pessoa na mesma atribuição; autor não
  recebe; seguidor com `mute` no robô não recebe; grep-guard da string observadora. (§D-P7 — os dois
  textos coexistem por destinatário)

## 6. Eventos estruturais — item pendente 2 (G6) 🔴 — MIGRAÇÃO (reversão NÃO-trivial) — **DEFERIDO**

> **DEFERIDO por decisão do dono (2026-07-30):** este grupo é o único com migração de reversão
> **NÃO-trivial** (`ALTER TYPE notification_type ADD VALUE 'structure'` — Postgres não tem
> `DROP VALUE`). Fica ABERTO aguardando aprovação separada. Os grupos reversíveis (G1–G5, G7)
> foram executados sem ele. Retomar só com OK explícito.

- [ ] 6.1 Migration `disable_ddl_transaction!` com `ALTER TYPE notification_type ADD VALUE IF NOT
  EXISTS 'structure'`; `down` levanta `IrreversibleMigration` com a nota de que remover valor de
  enum PG exige recriar o tipo. Regenerar `structure.sql`. (§D-P8 — 🔴 é o ponto onde a reversão
  deixa de ser um `DROP` simples)
- [ ] 6.2 Chaves de locale estruturais (`structure_<entidade>_<ação>`, 3ª pessoa) e o
  `MessageBuilder`/serviço que as renderiza a partir da ação + rótulo da entidade. (§D-P8 — texto
  materializado; ação/entidade no texto, não no enum)
- [ ] 6.3 Instrumentar `structure.changed` pós-commit nos services de hierarquia (criar/editar/
  excluir projeto/célula/robô/tarefa) com `workspace_id`, `actor_person_id`, `ctx`, ação e rótulo;
  subscriber → `NotifyStructureEventJob` (fila `:notifications`). Escopo inicial: **create + delete**
  (update sob decisão O-8). (§D-P8 — rollback não instrumenta; só create/delete no v1)
- [ ] 6.4 Recipientes estruturais = dono + seguidores do galho − autor, honrando `mute` (reusa o
  `SubscriptionResolver` com `default` = "é o dono"). (§D-P8 — dono recebe exclusão de robô; galho
  silenciado não recebe; autor não se notifica)
- [ ] 6.5 Specs: enum aceita `structure`/recusa arbitrário; dono recebe exclusão; galho silenciado
  não; autor não; rollback não enfileira. (§D-P8 — cobre os cinco cenários do spec delta)

## 7. Fechamento (G7) 🟢

- [ ] 7.1 Rodar a suíte completa da change (banco SQL cru, resolver/filtro, API/negações, UI, assign
  observador, estrutural) e registrar o resultado. (Método da casa — verde exige simultaneamente:
  RLS isola, mais-específico-vence, dono recebe 3ª pessoa, silenciador responsável some)
- [ ] 7.2 Atualizar `CONTINUIDADE.md` (estado/suítes/tip) e a EXTENSÃO de
  `in-app-notifications/EXECUCAO.md` (os dois itens pendentes agora fechados), e validar
  `validate notification-preferences --strict`. (Regra da casa — doc é parte do push)
