## Context

O `in-app-notifications` foi desenhado com preferências como **não-objetivo explícito**
("o legado não tem; não inventamos"). O dono agora pede o oposto, e a forma importa: a
preferência é **por entidade da hierarquia**, não por tipo. Três dificuldades reais:

1. **Onde o filtro entra sem quebrar as invariantes.** O pipeline tem uma ordem sagrada
   (montar bruto → dedup → subtrair autor → best-effort pós-commit). A preferência precisa
   **adicionar seguidores** e **remover silenciadores** sem tocar em "nunca o autor", na
   dedup, na RLS, nem no fato de que falhar a notificação não pode derrubar o avanço.
2. **A herança.** "Seguir um robô dentro de um projeto silenciado" e "silenciar um robô
   dentro de um projeto seguido" têm que funcionar as duas. Isso exige uma regra de
   precedência entre níveis — e um DEFAULT quando não há linha nenhuma.
3. **Os dois itens do dono empurram no limite de migração.** Um deles (atribuição a
   terceiros) **não** precisa de migração de enum se a mensagem for materializada por
   destinatário; o outro (estrutural) precisa. Separar os dois é o que deixa a reversão
   barata onde dá.

## Goals / Non-Goals

**Goals**
- Preferência por pessoa, por entidade (projeto/célula/robô), com herança "mais específico
  vence" e DEFAULT que preserva o comportamento atual.
- Integridade referencial e isolamento de tenant no banco (FK composta + RLS forçada),
  no mesmo idioma das demais tabelas.
- O filtro de preferência entra num único ponto do pipeline, sem regredir invariantes.
- Fechar os dois itens do dono, **isolando** a parte que exige migração de enum (estrutural).

**Non-Goals**
- Preferência por tipo de notificação (`progress` vs `done`).
- Guarda de "própria linha" no banco (é política, como o `mark_read?` — ver D-P6).
- Idempotência de eventos estruturais sob retry (best-effort; se duplicar sob retry raro,
  a UI dedup por id — pode virar índice único depois).

## Decisions

### D-P1 — Alvo por TRÊS colunas FK, não polimórfico textual

`notification_subscriptions` referencia o alvo por `scope_project_id` / `scope_cell_id` /
`scope_robot_id`, exatamente **uma** não-nula (CHECK `num_nonnulls(...) = 1`). Cada uma é
FK **composta** com `workspace_id` (`(scope_x_id, workspace_id) REFERENCES x(id, workspace_id)`).

*Alternativa descartada:* `target_type text + target_id uuid` (polimórfico). Rejeitada pelo
mesmo motivo que o `ctx` de `notifications` virou 4 colunas e não jsonb (D-N2): polimórfico
**perde a FK** — uma preferência apontando para um robô excluído vira lixo pendurado; e a casa
proíbe endereçar por texto o que tem identidade (config §Convenções). Três colunas dão
`ON DELETE CASCADE` de graça: apagar o robô apaga as preferências dele.

*Onde mora:* CHECK + 3 FKs compostas na migration.

### D-P2 — Estado `follow`/`mute` como enum PG

`state notification_subscription_state NOT NULL` (enum PG `('follow', 'mute')`). Ausência de
linha **não** é um terceiro valor de enum — é a ausência, que cai no DEFAULT (D-P3). Isso
mantém o enum com dois valores honestos e deixa "padrão" ser representado por **apagar a
linha** (idempotente).

*Alternativa descartada:* `boolean muted`. Rejeitada porque `follow` e `mute` não são
complementares — `follow` inverte o default para não-responsáveis (ativa), `mute` inverte
para responsáveis (desativa). Um booleano perderia a intenção "seguir mesmo sem ser
responsável".

### D-P3 — Resolução: o mais específico vence; DEFAULT = responsável-ou-dono

Para a pessoa X e uma notificação no galho `(project P, cell C, robot R)`:

1. Procura a linha de X em **R**; se existe, `follow ⇒ recebe`, `mute ⇒ não recebe`. Fim.
2. Senão, procura em **C**; decide igual. Fim.
3. Senão, procura em **P**; decide igual. Fim.
4. Sem nenhuma linha → **DEFAULT**: `recebe` se X é responsável pela tarefa **ou** é o dono
   do workspace (nos avanços, a EXTENSÃO); senão `não recebe`.

Isso torna a herança correta por construção: um `mute` no projeto e um `follow` no robô →
o robô (mais específico) vence → recebe. O DEFAULT preserva 100% do comportamento de hoje
quando a tabela está vazia.

*Alternativa descartada:* "qualquer mute no galho silencia" (mute vence sempre). Rejeitada
porque impede *seguir um robô dentro de um projeto silenciado*, que é exatamente um caso que
o dono descreveu ("aquele robô").

*Onde mora:* função pura `Notifications::SubscriptionResolver.wants?(person_id, ctx, default:)`
com teste de tabela; os dados vêm de uma única query por evento (D-P5).

### D-P4 — Onde o filtro entra: depois dos candidatos, dentro de `CreateService`

O `CreateService#insert_for` já resolve o `ctx` (project/cell/robot/task). O filtro entra ali,
em três passos, preservando a ordem sagrada:

```
candidatos = RecipientResolver.resolve(...) ∪ with_owner(...)   # default = quem está aqui
seguidores = SubscriptionResolver.followers(ctx)                # pessoas com follow no galho
universo   = (candidatos ∪ seguidores).uniq − [actor]           # nunca o autor, dedup — INALTERADO
final      = universo.select { |pid| SubscriptionResolver.wants?(pid, ctx, default: candidatos.include?(pid)) }
```

- **"Nunca o autor"** continua sendo a subtração de `actor` — aplicada ao universo inteiro,
  então um seguidor que também é o autor não se auto-notifica.
- **Dedup** continua `uniq`.
- **Best-effort** intacto: o filtro roda dentro do job pós-commit; a query extra é uma leitura
  sob RLS; se `notification_subscriptions` estiver indisponível, o job falha e retenta — o
  avanço já commitou.
- **RLS**: a query de preferências roda no contexto de tenant do job (mesmo `workspace_id`).

*Alternativa descartada:* filtrar **dentro** do `RecipientResolver` (torná-lo impuro, lendo o
banco). Rejeitada — o resolver é uma função pura testável (§3.1 de `in-app-notifications`);
mantê-lo puro e pôr o filtro no `CreateService` (que já é impuro, faz `ctx` e insere) preserva
a testabilidade.

*Onde mora:* `SubscriptionResolver` (novo objeto puro para `wants?` + um carregador de linhas)
chamado por `CreateService`; specs de tabela.

### D-P5 — Uma query por evento

`SubscriptionResolver` carrega **todas** as linhas relevantes ao galho numa consulta:

```sql
SELECT person_id, scope_project_id, scope_cell_id, scope_robot_id, state
FROM notification_subscriptions
WHERE scope_project_id = :p OR scope_cell_id = :c OR scope_robot_id = :r;
```

Depois, em Ruby, agrupa por `person_id` e escolhe o nível mais específico. Os índices parciais
de lookup (`scope_*_id WHERE ... IS NOT NULL`) tornam cada ramo do OR barato. É **uma** query
adicional por evento de notificação — aceitável num job best-effort fora do caminho do save.

### D-P6 — API pessoal: cada um edita só a própria preferência (invariante 4 vizinha)

- `GET /api/v1/notification_subscriptions` → as linhas da **própria** pessoa (para hidratar os
  sinos das telas). Escopo `person_id = current_person`.
- `PUT /api/v1/notification_subscriptions` body `{ scope_type, scope_id, state }`:
  `follow`/`mute` fazem **upsert** (índice único parcial garante uma linha por alvo);
  `state: 'default'` **apaga** a linha.
- **Nenhum** endpoint que edite a preferência de outra pessoa.
- `NotificationSubscriptionPolicy`: nova action de matriz `manage_own_subscription`, autorizada
  para `owner`/`edit`/`view` (é preferência pessoal, não mutação de domínio — mesma classe do
  `mark_notification_read`), **e** o registro precisa ter `person_id == context.person.id`
  (idioma idêntico ao `mark_read?`).

*Sobre a invariante 4* ("a única mutação de um membro `view` é marcar a própria notificação como
lida"): esta change **amplia** a superfície de escrita do `view` para incluir a própria
preferência. Registro consciente: a invariante 4 fala do registro `notifications`; a preferência
é uma tabela nova, **self-scoped** (só a própria linha), sob RLS forçada, sem efeito cross-tenant
nem sobre dado de domínio. É a mesma natureza da leitura ("marcar lida") — configuração pessoal,
não autoria. **Decisão em aberto O-5** propõe ao dono confirmar se o `view` deve poder calibrar
as próprias notificações (recomendação: sim).

*Guarda de "própria linha":* é **política**, não banco — exatamente como o `mark_read?`
(ownership por policy; o banco força tenant e, no caso de `notifications`, colunas por trigger).
Não há `app.current_person_id` na RLS hoje; introduzi-lo seria infra nova fora de escopo.

### D-P7 — Item pendente 1 (atribuição a terceiros) SEM migração de enum

A EXTENSÃO de `in-app-notifications` registrou que notificar o dono de uma atribuição
"exigiria uma string nova → novo `type` → migração". **Reavaliação:** a `msg` é **materializada
por destinatário** no `insert_one`. Basta renderizar por destinatário:

- ao **atribuído** (o delta): `assign` em 2ª pessoa (`%{author} atribuiu você…`) — como hoje.
- ao **dono/seguidores** (não-atribuídos, não-autor): uma chave nova `assign_observer` em 3ª
  pessoa (`%{author} atribuiu %{assignee} à tarefa "%{task}" (robô %{robot})`).

O **valor de enum continua `assign`** nos dois casos — só a chave de locale e o `format_version`
mudam. O índice de idempotência de `assign` (`(recipient, ctx_task, type, recorded_at) WHERE
type='assign'`) segue válido (o destinatário difere). **Zero migração.** É um ganho sobre o
plano conservador da EXTENSÃO.

*Consequência:* `insert_for` passa a construir a `msg` **por destinatário** no caso `assign`
(hoje constrói uma vez para todos). Refactor pequeno, sem banco.

*Decisão em aberto O-4:* o **atribuído** honra `mute`? Recomendação: **não** — ser atribuído é
evento direto e acionável sobre você; `mute` de um galho suprime o fluxo ambiente (progress/done/
estrutural e o `assign_observer`), mas o `assign` **para o próprio atribuído** sempre dispara.

### D-P8 — Item pendente 2 (eventos estruturais) COM migração de enum

Criar/editar/excluir projeto/célula/robô/tarefa não emitem evento hoje. Passam a:

1. `ActiveSupport::Notifications.instrument('structure.changed', ...)` pós-commit nos services de
   hierarquia (mesmo idioma dos publishers de `task.advanced`), com `workspace_id`, `actor_person_id`,
   `ctx` (project/cell/robot/task conforme o nível) e a ação (`created`/`updated`/`deleted`) + o
   rótulo da entidade.
2. Um subscriber enfileira `NotifyStructureEventJob` (fila `:notifications`).
3. **Enum:** `ALTER TYPE notification_type ADD VALUE 'structure'` — **UM** valor coarse; a ação
   e a entidade vão no texto materializado (não em granularidade de enum). Chaves de locale
   `structure_project_created`, `structure_robot_deleted`, etc.
4. Destinatários: **dono + seguidores** do galho afetado, menos o autor, honrando `mute` (D-P3
   com `default` = "é o dono"). O responsável de tarefa **não** é destinatário estrutural por
   default (estrutural é sobre a forma da hierarquia, interesse de gestor/seguidor).

*Por que UM valor de enum e não vários* (`structure_created`/`_updated`/`_deleted`): o `type`
serve para idempotência, filtro e ícone — nenhum precisa distinguir a ação, que já está no
texto. Menos valores = menor superfície irreversível.

*Migração NÃO-trivial:* `ALTER TYPE ADD VALUE` não roda dentro de transação que já usa o valor
(migration com `disable_ddl_transaction!`), e **remover** um valor de enum PG exige recriar o
tipo (não há `DROP VALUE`). É o **único** ponto desta change onde o `down` não é um `DROP`
simples. Marcado em `tasks.md` (G6) e chamado no relatório ao dono.

*Decisão em aberto O-8:* quais ações estruturais notificam? Recomendação: **create** e **delete**
sempre (nascimento/morte de galho importam); **update** (renomear) só se o dono quiser — tende a
ruído. Começar com create/delete e adicionar update sob pedido.

### D-P9 — UX: sino de estado nas três telas (impeccable, register `product`)

O controle mora no **cabeçalho da página da própria entidade** (não nos cards — evita poluição e
a regra G de nome de botão duplicado):

- **Robô:** `RobotTaskTablePage` `<header>` (ao lado do Badge de aplicação / % ponderado).
- **Célula:** `CellPage` (junto de "Adicionar robôs").
- **Projeto:** `ProjectPage` (junto de "Nova célula").
- **Workspace (opcional, O-7):** `OverviewPage` — um "silenciar tudo" de nível workspace exigiria
  um 4º alvo (`scope_workspace`); **fora do v1** salvo pedido.

Forma (DESIGN.md: badge é rótulo, seletor é controle — nunca se parecem; alvo ≥40px de luva;
`prefers-reduced-motion`): um **`IconButton`** (sino) que abre um **`PortalMenu`** com três itens
explícitos — **Padrão**, **Seguir**, **Silenciar** — cada um com descrição de uma linha. **Não** um
toggle que cicla no toque: sob luva, ciclar 3 estados por toque é ambíguo; três alvos ≥40px num
menu são inequívocos e navegáveis por teclado/leitor (mesmo primitivo do sino de notificações).

Estado **efetivo com origem** (estado honesto, Princípio 2): o ícone reflete o estado resolvido
para aquela entidade —

- **Padrão** (sem linha própria e sem herança): sino contorno neutro. Tooltip: "Notificações no
  padrão — você recebe se for responsável."
- **Seguindo** (follow próprio, ou herdado de um pai): sino cheio/accent. Se herdado: "Seguindo
  pelo projeto".
- **Silenciado** (mute próprio, ou herdado): sino cortado (`bell-off`), cor muda. Se herdado:
  "Silenciado pelo projeto".

Ícone `bell-off` **não existe** no sprite — adicionar `<symbol id="i-bell-off">` + `ICON_NAMES`
(currentColor, sem emoji — regra do projeto). Cópia pt-BR em `src/lib/i18n/notifications.ts`
(arquivo novo; hoje as strings do centro estão inline — esta change cria o arquivo canônico e
move os rótulos para lá). Sem literal solto (regra da casa).

Hook `useNotificationSubscriptions` espelhando `useNotifications`: query key
`qk.subscriptions(wsId)` = `['ws', wsId, 'subscriptions']` (passa no `query-convention` sweep),
mutação otimista de `PUT` (molde de `useDeleteRobot`/`useRenameProject`), invalidando a chave
específica. O sino de cada tela lê o estado efetivo daquela entidade a partir das linhas
carregadas.

### D-P10 — Owner-recebe-tudo convive com preferências, sendo sobreposto por `mute`

A EXTENSÃO fez o dono receber **todos** os avanços do workspace. Com preferências, isso vira o
**DEFAULT do dono** (D-P3: dono ⇒ recebe), e uma linha `mute` explícita do dono em qualquer nível
**sobrepõe** (mais-específico-vence). Ou seja: o dono continua recebendo tudo por padrão, mas ganha
o poder de silenciar um projeto barulhento — o que é justamente o que falta hoje. **Decisão em
aberto O-3** confirma essa sobreposição (recomendação: sim).

## Plano de migração (a APROVAR)

Migration única de G1 — `db/migrate/20260726NNNNNN_create_notification_subscriptions.rb`,
`ActiveRecord::Migration[8.0]`, SQL cru (idioma das demais tabelas de tenant), `structure.sql`
regenerado. **Não destrutiva** (tabela + enum novos). SEM GRANT (o `robotrack_migrator` já
concede DML por default-privileges ao `robotrack_app` — `db/roles.sql`). SEM REVOKE (tabela
mutável, não append-only).

```sql
CREATE TYPE notification_subscription_state AS ENUM ('follow', 'mute');

CREATE TABLE notification_subscriptions (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id      uuid NOT NULL REFERENCES workspaces (id) ON DELETE CASCADE,
  person_id         uuid NOT NULL,
  scope_project_id  uuid,
  scope_cell_id     uuid,
  scope_robot_id    uuid,
  state             notification_subscription_state NOT NULL,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT chk_notif_sub_one_scope
    CHECK (num_nonnulls(scope_project_id, scope_cell_id, scope_robot_id) = 1),

  CONSTRAINT fk_notif_sub_person
    FOREIGN KEY (workspace_id, person_id)
    REFERENCES people (workspace_id, id) ON DELETE CASCADE,
  CONSTRAINT fk_notif_sub_project
    FOREIGN KEY (scope_project_id, workspace_id)
    REFERENCES projects (id, workspace_id) ON DELETE CASCADE,
  CONSTRAINT fk_notif_sub_cell
    FOREIGN KEY (scope_cell_id, workspace_id)
    REFERENCES cells (id, workspace_id) ON DELETE CASCADE,
  CONSTRAINT fk_notif_sub_robot
    FOREIGN KEY (scope_robot_id, workspace_id)
    REFERENCES robots (id, workspace_id) ON DELETE CASCADE
);

-- Exigido pela guarda de RLS + acelera o filtro por tenant
CREATE INDEX index_notification_subscriptions_on_workspace_id
  ON notification_subscriptions (workspace_id);

-- Uma preferência por pessoa por alvo (idempotência do upsert)
CREATE UNIQUE INDEX uq_notif_sub_person_project
  ON notification_subscriptions (person_id, scope_project_id) WHERE scope_project_id IS NOT NULL;
CREATE UNIQUE INDEX uq_notif_sub_person_cell
  ON notification_subscriptions (person_id, scope_cell_id)    WHERE scope_cell_id    IS NOT NULL;
CREATE UNIQUE INDEX uq_notif_sub_person_robot
  ON notification_subscriptions (person_id, scope_robot_id)   WHERE scope_robot_id   IS NOT NULL;

-- Lookup do resolver: dado um galho, todas as linhas relevantes por nível
CREATE INDEX idx_notif_sub_by_project ON notification_subscriptions (scope_project_id) WHERE scope_project_id IS NOT NULL;
CREATE INDEX idx_notif_sub_by_cell    ON notification_subscriptions (scope_cell_id)    WHERE scope_cell_id    IS NOT NULL;
CREATE INDEX idx_notif_sub_by_robot   ON notification_subscriptions (scope_robot_id)   WHERE scope_robot_id   IS NOT NULL;

-- RLS forçada — idioma idêntico às demais tabelas de tenant
ALTER TABLE notification_subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE notification_subscriptions FORCE  ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON notification_subscriptions
  USING      (workspace_id = NULLIF(current_setting('app.current_workspace_id', true), '')::uuid)
  WITH CHECK (workspace_id = NULLIF(current_setting('app.current_workspace_id', true), '')::uuid);
```

Migração de G6 (SEPARADA, e a que trava a reversão) —
`db/migrate/20260726NNNNNN_add_structure_to_notification_type.rb`, `disable_ddl_transaction!`:

```ruby
def up
  execute "ALTER TYPE notification_type ADD VALUE IF NOT EXISTS 'structure'"
end
def down
  # ALTER TYPE ... DROP VALUE não existe no Postgres. Reverter exige recriar o
  # tipo notification_type sem 'structure' e recompor todas as colunas que o usam
  # — NÃO-trivial. Ver tasks.md G6.
  raise ActiveRecord::IrreversibleMigration
end
```

## Riscos / Trade-offs

- **Ampliação da superfície de escrita do `view`** (D-P6). Mitigado: self-scoped, RLS forçada,
  política de "própria linha". Decisão O-5 pede confirmação do dono.
- **`update` estrutural pode ser ruído** (renomear dispara sino). Mitigado por O-8 (começar sem
  update).
- **Reversão de G6 não-trivial** (`ALTER TYPE ADD VALUE`). Aceito e marcado; é o preço de manter
  `notification_type` como enum PG (a alternativa — migrar para texto+CHECK — é maior e fora de
  escopo).
- **Sino "efetivo com origem" exige subir a cadeia** (robô herda de célula/projeto). Custo: as
  linhas do galho já vêm na resposta do `GET`; a resolução de origem é no cliente, barata.
- **Query extra por evento** (D-P5). Aceito: best-effort, fora do caminho do save, indexada.

## Perguntas em aberto (para o dono — cada uma com recomendação)

- **O-1 (default):** responsável/dono recebe; não-responsável não recebe salvo `follow`.
  **Recomendação: adotar** (preserva o comportamento atual; menor surpresa).
- **O-2 (herança):** o nível mais específico com preferência vence.
  **Recomendação: adotar** (habilita "seguir robô em projeto silenciado", pedido do dono).
- **O-3 (owner-recebe-tudo × mute):** `mute` do dono sobrepõe o "recebe tudo".
  **Recomendação: sim** (dá ao dono o poder de calar um projeto barulhento).
- **O-4 (assign × mute):** o **atribuído** sempre recebe seu `assign`; `mute` só afeta o fluxo
  ambiente (progress/done/estrutural/`assign_observer`). **Recomendação: sim**.
- **O-5 (`view` calibra?):** membro `view` pode ter preferências próprias (amplia a invariante 4
  para uma tabela self-scoped nova). **Recomendação: sim** (é config pessoal, não autoria).
- **O-6 (item 1 sem migração):** notificar atribuição a terceiros via chave de locale
  `assign_observer` mantendo `type='assign'` — **sem** migração de enum. **Recomendação: adotar**
  (evita `ALTER TYPE` para o item 1; só o item 2 fica com migração).
- **O-7 (alvo workspace?):** oferecer "silenciar o workspace inteiro" (4º alvo `scope_workspace`).
  **Recomendação: não no v1** (três níveis cobrem o pedido; adicionar depois se necessário).
- **O-8 (ações estruturais):** notificar `create` + `delete` já; `update`/renomear só sob pedido.
  **Recomendação: começar com create/delete**.
