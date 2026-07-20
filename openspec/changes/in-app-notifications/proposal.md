## Why

O legado notifica em três eventos (§2.7) e endereça o destinatário **por nome de
pessoa** — o mesmo texto usado em `assignees`, com o sentinela `"Não Atribuído"`
circulando como se fosse gente. A entidade Notificação de §1.1 carrega
`target`, `type`, `msg`, `byName`, `ts`, `tsLocal`, `read` e `ctx` (`{pid, cid,
rid, tid}`), e a invariante 8 de §4.1 exige `msg ≤ 500` e `read: false` na
criação. A invariante 4 de §4.1 é mais estreita e mais afiada do que parece: a
**única** mutação que um membro `view` pode fazer em todo o sistema é marcar a
*própria* notificação como lida — no `firestore.rules` isso é literalmente
`request.resource.data.diff(resource.data).affectedKeys().hasOnly(['read'])`
(linhas 61–62).

Nada disso sobrevive ao porte por conta própria. As Firestore rules eram a única
guarda de `msg.size() <= 500` e `read == false`; sem elas, e sem constraint no
Postgres, essas invariantes viram validação de model — contornável por console,
por `update_column`, por import legado. E o pedaço mais frágil do
comportamento não está no servidor: o **alerta do sistema operacional** só pode
disparar para itens *novos*. Recarregar a página com 10 não lidas antigas tem
que produzir zero alertas; a implementação ingênua ("notifique tudo que estiver
`read: false`") passa em toda revisão de código e falha no primeiro F5.

Esta capacidade traduz do Firebase: as regras de `match /notifications/{notifId}`
viram policy + CHECK constraint + coluna-a-coluna no update; o `onSnapshot` que
entregava notificação nova em tempo real vira dependência declarada de
`realtime-collaboration` (D6).

## What Changes

- **Tabela `notifications`** (uuid PK — D1/D13; `workspace_id NOT NULL` + RLS —
  D2). **BREAKING vs. §1.1:** `target` deixa de ser nome e vira
  `recipient_person_id` (FK → `people`), por D10/D11. `"Não Atribuído"` não é
  destinatário porque não existe (D11).
- Esquema **completo** da entidade: `type` (`assign`|`progress`|`done`), `msg`,
  `author_name_snapshot` (`byName`), **`recorded_at` (`ts`) e `ts_local`
  (`tsLocal`)** — os dois timestamps, D8, mais o texto pré-formatado do legado —,
  `read_at`/`read`, e `ctx` desnormalizado em quatro colunas
  (`project_id`, `cell_id`, `robot_id`, `task_id`).
- **CHECK constraints** para as invariantes 8 e 4: `char_length(msg) <= 500` e
  `read = false` na criação (via trigger `BEFORE INSERT`, já que CHECK não
  distingue INSERT de UPDATE).
- **Três regras de disparo (§2.7)** com **format strings versionadas** em
  `config/locales/pt-BR.notifications.yml` (D14), não literais espalhados:
  `assign`, `progress`, `done`.
- **Regras transversais**: nunca notifica o autor; destinatários deduplicados;
  progresso `0` não gera notificação; entrega é **best-effort** e não pode
  derrubar o save.
- **Centro de notificações** na UI (badge de não lidas, lista, marcar como lida,
  marcar todas) e navegação por `ctx` até o robô da tarefa.
- **Alerta do SO** (Notification API) apenas para itens novos, com foco do app e
  navegação ao clicar.
- **Política de retenção** declarada — e explicitamente delegada.

### Não-objetivos

- **E-mail, push (Web Push/FCM), SMS.** Só in-app + alerta local do SO. Web Push
  exige service worker + VAPID + fila de retentativa; fica fora.
- **Transporte em tempo real.** O `WorkspaceChannel` e a invalidação de query key
  são de `realtime-collaboration` (D6). Aqui declaramos o *evento publicado* e o
  *contrato do payload*; quem transporta é a outra capacidade.
- **Preferências por tipo de notificação** ("não me avise de `progress`"). O
  legado não tem; não inventamos.
- **Digest/agrupamento** ("3 avanços na tarefa X"). Fora.
- **O job de expurgo em si.** Ver Impact.
- **Gerar os eventos.** Quem chama o notificador é `progress-advances` (avanço) e
  `robot-tasks` (atribuição). Aqui definimos a interface que eles chamam.

## Capabilities

### New Capabilities

- `in-app-notifications`: modelo, as três regras de disparo, destinatários e
  dedup, invariantes 4 e 8 no banco, API de listagem e marcação como lida,
  centro de notificações na UI.
- `notification-os-alerts`: integração com a Notification API do navegador —
  permissão, disparo **apenas para itens novos**, e navegação por `ctx` ao
  clicar.

### Modified Capabilities

(nenhuma — `openspec/specs/` está vazio)

### Impact

- **Depende de** `progress-advances` (Onda 5): o disparo de `progress`/`done`
  acontece no mesmo fluxo do avanço, e `recorded_at` vem de D8.
- **Depende de** `robot-tasks`: o disparo `assign` precisa do delta de
  `task_assignees`, e ele é calculado lá.
- **Depende de** `workspace-tenancy`: `Person` (D10), `workspace_id`, RLS (D2).
- **Depende de** `authorization-policies` (D3): `NotificationPolicy` entra na
  matriz §4.1 e no route-sweep.
- **Depende de** `quality-and-accessibility` (D14) para o arquivo de locale, e do
  `aria-live` do centro de notificações.
- **Consumida por** `realtime-collaboration` (Onda 8) e `app-shell-navigation`
  (o sino mora na topbar).
- **Entrega:** o disparo roda em job Sidekiq (`notifications` queue) — exige fila
  nomeada e concorrência configuradas em produção, mais alerta de fila crescendo.
  **Cita `delivery-and-observability`**, que também é dona do job de retenção:
  notificações crescem sem limite e nada as expurga hoje. Definimos aqui a
  política (`read = true` e `recorded_at < now() - 90 dias` são elegíveis;
  não lidas nunca são expurgadas automaticamente) e o índice que a torna barata;
  o cron que a executa é de lá.
