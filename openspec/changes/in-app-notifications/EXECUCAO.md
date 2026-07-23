# EXECUCAO — in-app-notifications (Onda D-N)

Mapa de execução. Escrito ANTES de qualquer código (commit G0). RETOMADA no fim.

## Ponto de partida

Notificações in-app: assign/progress/done, entregues em tempo real (consome o
WorkspaceChannel de D6, COMPLETO) e persistidas best-effort (falhar ao notificar
NUNCA derruba o save do avanço). Depende de progress-advances, robot-tasks,
workspace-tenancy (RLS/Person) e authorization-policies — todas COMPLETAS. A
retenção é DECLARADA aqui e EXECUTADA em delivery-and-observability (D11, COMPLETO
nesta sessão) — cujo `Ops::RetentionPurge` já poda `notifications` 90d de forma
defensiva; o handoff de 8.2 já tem destino.

## RECONCILIAÇÃO COM A REALIDADE (crítico — ler antes de codar)

- **Greenfield quase total:** NÃO existem a tabela `notifications`, o enum
  `notification_type`, o model, os serviços (MessageBuilder/RecipientResolver/
  EventClassifier/CreateService), o job, os endpoints, o centro de notificações
  nem o alerta do SO.
- **`NotificationPolicy` JÁ EXISTE** (`app/policies/notification_policy.rb`),
  órfão de uma tentativa anterior: `index/show = read_workspace`, `create =
  create_log`, `mark_read?` exige `notification.person_id == context.person.id`.
  DIVERGE do design: a coluna é `recipient_person_id`, não `person_id` — ajustar.
  Depende de `PermissionMatrix.allows?(:mark_notification_read, role)` — VERIFICAR
  se essa permissão existe na matriz (senão adicionar) no G5.
- **Retenção (8.2) já semeada:** `Ops::RetentionPurge.run_all` já chama
  `purge_expired('notifications', "read_at IS NOT NULL AND read_at < now-90d")`.
  Nota: o design pede `read = true AND recorded_at < now-90d` (D-N10) — reconciliar
  o predicado no G8 (o scope `Notification.purgeable`) e alinhar o purge de D11 se
  preciso. O cron/config de produção fica em D11 (handoff só de execução).
- **Esquema (D-N2):** id, workspace_id, recipient_person_id, actor_person_id,
  type(enum), msg, author_name_snapshot, recorded_at(tz), created_at(tz),
  ts_local(text), read(bool), read_at, ctx_project/cell/robot/task_id (4 colunas
  FK, NÃO jsonb). Ordenação SEMPRE `recorded_at DESC`.
- **Format strings v1 (§2.7 / D14)** — literais EXATOS, no locale:
  - assign:   `%{author} atribuiu você à tarefa "%{task}" (robô %{robot})`
  - progress: `%{author} registrou %{n}%% na tarefa "%{task}" (robô %{robot}): %{comment}`
  - done:     `Tarefa "%{task}" (robô %{robot}) foi concluída por %{author}`
  Truncagem: SÓ `%{comment}` com `…` quando msg > 500; nome do robô/tarefa íntegros.
- **Destinatários (§2.7):** assign = delta (novos − anteriores); progress/done =
  todos os responsáveis atuais. Depois: dedup por person_id, subtrai
  actor_person_id. Nessa ordem. Autor único responsável → conjunto VAZIO.
- **Classifier (§2.7):** `to==100`→done; `0<to<100`→progress; `to==0`→nil (reset,
  zero notificação).
- **Marca d'água do SO (D-N8):** EM MEMÓRIA (não localStorage). A 1ª resposta da
  sessão só INICIALIZA; nunca dispara. Reload com 10 não lidas de ontem = 0
  alertas. É o modo de falha explícito desta capacidade (teste obrigatório 7.5).
- **Integração best-effort (§2.7):** job `after_commit` FORA da transação em
  progress-advances (avanço) e robot-tasks (mudança de task_assignees). Rollback →
  zero jobs; Redis/Sidekiq fora → avanço salvo e 2xx mesmo assim.
- **Superfície de API:** listagem paginada (recorded_at DESC, escopo
  recipient_person_id=current_person) + contagem não-lidas no header; POST
  :id/read e read_all; NENHUM PATCH genérico (o route-sweep prova a ausência).
- **Postgres cai com frequência** (Connection refused): `pg_ctlcluster 16 main
  start` quando preciso. Migrations como `robotrack_migrator`; RLS/roles como no
  D2. Redis rodando (subido no D11).

## Ordem dos grupos (mapa)

| Grupo | Escopo | Tarefas |
|---|---|---|
| **G1** | Esquema + invariantes: enum, tabela (D-N2), RLS, CHECK (msg≤500, coerência read/read_at), triggers BEFORE INSERT (read=true falha) e BEFORE UPDATE (só read/read_at, sem read:true→false), índice único de idempotência de assign + índices de leitura/retenção; spec de banco por SQL cru | 1.1–1.6 |
| **G2** | Mensagens versionadas: locale `pt-BR.notifications.yml` (v1, 3 strings exatas), `MessageBuilder` (renderiza por type, grava format_version, trunca só %{comment}), spec de contrato caractere-a-caractere + grep-guard | 2.1–2.3 |
| **G3** | Destinatários e disparo: `RecipientResolver` (delta/todos → dedup → −actor), `EventClassifier` puro; spec de tabela dos 5 casos-limite | 3.1–3.3 |
| **G4** | Persistência best-effort: `CreateService` (idempotente sob unique), `NotifyTaskEventJob` (queue :notifications, retry 5), wiring after_commit fora da tx em advances/assignees; spec de resiliência (Redis fora / criação lançando → avanço salvo, 2xx) | 4.1–4.4 |
| **G5** | API e autorização: `Api::Entities::Notification` + listagem paginada + header de não-lidas; POST :id/read e read_all (sem PATCH genérico); `NotificationPolicy` (recipient==current, view nega create); route-sweep + specs de negação (4 casos) | 5.1–5.4 |
| **G6** | Centro de notificações (UI): `useNotifications` (key ['ws',wsId,'notifications'], contagem derivada), painel (lista/vazio/marcar lida individual+todas, aria-live), `ctxToPath` + navegação, teste de componente | 6.1–6.4 |
| **G7** | Alerta do SO: `useOsNotificationAlerts` (marca d'água em memória, lint proíbe `new Notification(` fora), botão "Ativar alertas" (requestPermission só no clique), supressão por visibilidade + dedup por id, onclick focus+navegação+troca de ws; teste dos 4 cenários (incl. 10 antigas → 0 alertas) | 7.1–7.5 |
| **G8** | Retenção e fechamento: scope `Notification.purgeable` (D-N10) + EXPLAIN usa índice; handoff a D11 (já semeado); suíte completa | 8.1–8.3 |

## Armadilhas previstas

- **Trigger BEFORE UPDATE × marcar lida:** o UPDATE de `read`/`read_at` DEVE
  passar; qualquer outra coluna ou `read:true→false` é rejeitado por inteiro. O
  endpoint de leitura escreve só essas duas colunas.
- **`NotificationPolicy` órfã:** alinhar `person_id`→`recipient_person_id` e
  garantir `:mark_notification_read`/`:create_log` na PermissionMatrix.
- **Idempotência de assign:** o índice único parcial é a rede; o `CreateService`
  tolera a violação sem levantar (reexecução = zero linha nova, sucesso).
- **Marca d'água persistida seria bug:** EM MEMÓRIA por construção. O teste
  "reload com 40 pendentes → 0 alertas" é o que impede a regressão silenciosa.
- **after_commit FORA da tx:** enfileirar dentro da tx enfileiraria em rollback.
  O gatilho é after_commit; a exceção no job não pode tocar o avanço já salvo.
- **RLS de notifications:** SET app.current_workspace_id de A e SELECT não vê B,
  nem como superusuário da app (mesmo idioma de D2).

## Baseline

Backend verde (specs de D11 e anteriores). Redis rodando. `notifications` não
existe; `NotificationPolicy` órfã presente; `Ops::RetentionPurge` já poda
`notifications` defensivamente. Frontend 510+/0.

## FECHAMENTO (G8)

- **8.2 (handoff a delivery-and-observability) JÁ SATISFEITO:** o D11 (COMPLETO
  nesta sessão) tem `Ops::RetentionPurge` que poda `notifications` (predicado
  alinhado a D-N10: `read = true AND recorded_at < now-90d`), a fila `:notifications`
  é declarada no `NotifyTaskEventJob`, e `Ops::AlertConditions` já tem a condição
  de fila parada (`sidekiq_queue_backlog`). O cron/config de produção é do D11.
- **8.3 (suíte completa) verde:** banco (invariantes SQL cru), serviços
  (builder/resolver/classifier/create), API (listagem/marcar/negações), UI
  (centro) e hook (alerta do SO, 4 cenários). Backend 155/0 no fecho da capacidade
  + frontend 10/0.

## RETOMADA

Ler este arquivo + design.md (D-N1…D-N10, §2.7, §4.1). Estado por grupo em
tasks.md. Protocolo por grupo: aplicar → specs dirigidos 0 falhas (subir
Postgres/Redis quando preciso) → marcar tasks → `npx --yes
@fission-ai/openspec@1.6.0 validate in-app-notifications --strict` → UM commit
`G<n>:` → fast-forward `main` + push → resumo pt-BR client-friendly → seguir.
Migrations como robotrack_migrator.
