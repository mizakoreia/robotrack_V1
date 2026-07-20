## Context

§2.7 é curto e enganosamente simples: três linhas de tabela, cinco bullets de
regra transversal. A dificuldade está em três lugares que o texto não destaca.

**Primeiro**, o endereçamento. O legado usa `target` = nome de pessoa, o mesmo
texto de `assignees`, e a lista de responsáveis do workspace "sempre contém
`"Não Atribuído"`" (§1.1). Isso significa que o legado tinha um destinatário
fantasma e precisava descartá-lo explicitamente na hora de notificar. D10/D11
matam o problema na raiz: `Person` é identidade estável, ausência de responsável
é conjunto vazio, e portanto `recipient_person_id` é uma FK real.

**Segundo**, as invariantes. O `firestore.rules` (linhas 54–64) é a única guarda
existente de `read == false` e `msg.size() <= 500` — e a regra de update é
`affectedKeys().hasOnly(['read'])`, um teste de *diff*, não de valor. Portar isso
como `validates :msg, length: {maximum: 500}` seria um downgrade silencioso de
garantia.

**Terceiro**, e é o requisito que mais quebra na prática: o alerta do SO só vale
para itens novos. O estado "novo" não é uma propriedade da notificação (`read:
false` não serve — uma não lida de ontem não é nova), é uma propriedade da
*sessão do cliente*. Errar isso não gera exceção nem teste vermelho: gera 10
pop-ups do macOS toda vez que o engenheiro dá F5 no galpão.

## Goals / Non-Goals

**Goals**
- Notificação com esquema completo de §1.1, incluindo `ts` **e** `tsLocal` — o
  plano anterior esqueceu os dois na migration de notificações embora os tivesse
  lembrado na de auditoria.
- As três mensagens de §2.7 com **os formatos exatos**, versionados e testados.
  O plano anterior especificou destinatários e nunca especificou as strings,
  embora tenha especificado a string do log de auditoria — assimetria arbitrária
  que deixava a mensagem de notificação para o implementador improvisar.
- Invariantes 4 e 8 no **banco**.
- Zero alertas do SO na carga inicial, sob qualquer estado de leitura.
- Falha de notificação nunca derruba o save.

**Non-Goals**
- E-mail / Web Push / digest / preferências por tipo (ver proposal).
- Transporte realtime (D6, `realtime-collaboration`).
- O cron de expurgo (`delivery-and-observability`).
- Marcar como **não** lida. `read` é monotônico — simplifica o diff da invariante
  4 e o legado não oferece a ação.

## Decisions

### D-N1 — `recipient_person_id` (FK) em vez de `target` textual

`target` vira `recipient_person_id uuid NOT NULL REFERENCES people(id) ON DELETE
CASCADE`. Consequência de D10/D11.

*Alternativa descartada:* manter `target` como texto para fidelidade a §1.1.
Rejeitada porque renomear uma pessoa órfã todas as notificações dela, e porque
`"Não Atribuído"` seria um destinatário sintético que precisaria de um `if`
especial em três lugares. O nome do **autor** continua sendo texto
(`author_name_snapshot`), porque ali o snapshot histórico é o comportamento
correto — é o mesmo raciocínio de `byName` no avanço (§1.1).

*Onde mora:* FK + `ON DELETE CASCADE`. Remover a `Person` remove as notificações
dela; não há estado pendurado.

### D-N2 — Esquema completo, com os dois timestamps e `tsLocal`

```
notifications
  id                    uuid PK default gen_random_uuid()   -- D1/D13
  workspace_id          uuid NOT NULL REFERENCES workspaces -- D2, RLS
  recipient_person_id   uuid NOT NULL REFERENCES people
  actor_person_id       uuid NOT NULL REFERENCES people     -- para a regra "nunca o autor"
  type                  notification_type NOT NULL          -- enum PG: assign|progress|done
  msg                   text NOT NULL
  author_name_snapshot  text NOT NULL                       -- byName
  recorded_at           timestamptz NOT NULL                -- ts (D8: quando a pessoa agiu)
  created_at            timestamptz NOT NULL                -- D8: quando o servidor persistiu
  ts_local              text NOT NULL                       -- tsLocal formatado
  read                  boolean NOT NULL DEFAULT false
  read_at               timestamptz NULL
  ctx_project_id        uuid NULL REFERENCES projects
  ctx_cell_id           uuid NULL REFERENCES cells
  ctx_robot_id          uuid NULL REFERENCES robots
  ctx_task_id           uuid NULL REFERENCES tasks
```

`type` é **enum Postgres**, não string: valor fora de `assign|progress|done` é
erro de banco.

`ctx` é **quatro colunas**, não JSONB. *Alternativa descartada:* `ctx jsonb`,
fiel ao documento Firestore. Rejeitada porque perde integridade referencial
(um `ctx.rid` apontando para robô excluído gera link morto no centro de
notificações) e porque as quatro colunas ganham FK de graça.

`ts_local` é mantido apesar de redundante com `recorded_at` — §1.1 o lista, o
export legado o traz, e `legacy-data-migration` precisa de um destino para ele.
Ele é **texto de exibição histórico**, nunca fonte de ordenação; a ordenação é
sempre `recorded_at DESC`.

*Onde mora:* migration única, com `ts`/`tsLocal` presentes desde a criação — não
como retrofit.

### D-N3 — Invariantes 8 e 4 como CHECK + trigger, não validação de model

- Invariante 8, parte 1: `CONSTRAINT msg_max_500 CHECK (char_length(msg) <= 500)`.
- Invariante 8, parte 2 (`read: false` na criação): CHECK não distingue INSERT de
  UPDATE, então vai numa trigger `BEFORE INSERT` que **falha** (não corrige
  silenciosamente) se `NEW.read IS TRUE`.
- Coerência de `read_at`:
  `CHECK ((read = false AND read_at IS NULL) OR (read = true AND read_at IS NOT NULL))`.
- Monotonicidade: trigger `BEFORE UPDATE` rejeita `OLD.read = true AND NEW.read =
  false`.

*Alternativa descartada:* `validates :msg, length: { maximum: 500 }` e
`before_create { self.read = false }`. Rejeitada pela barra do projeto: model se
contorna por `update_column`, por `insert_all` e pelo importador legado — que é
exatamente o caminho por onde uma `msg` de 501 chars entraria.

A validação de model **também** existe, para dar erro 422 legível em vez de
`PG::CheckViolation` — mas ela é ergonomia, não a garantia.

### D-N4 — Invariante 4: `view` só muda `read`, e só da própria notificação

Porte de `affectedKeys().hasOnly(['read'])` (firestore.rules:62). Três camadas:

1. **Endpoint dedicado.** Não existe `PATCH /notifications/:id` genérico. Existe
   `POST /api/v1/notifications/:id/read` e `POST /api/v1/notifications/read_all`.
   Um endpoint que só sabe escrever uma coluna não pode escrever outra — é a
   tradução mais fiel de `hasOnly(['read'])`, porque remove a superfície em vez
   de filtrá-la.
2. **`NotificationPolicy`** (D3): `mark_read?` exige
   `notification.recipient_person_id == current_person.id`, para os **três**
   papéis (`owner`, `edit`, `view`). O dono do workspace **não** pode marcar como
   lida a notificação de outra pessoa — §4.1 diz "a **própria**", e a rule
   original também exigia `isMember()`, não ownership.
3. **Trigger `BEFORE UPDATE`** que rejeita qualquer UPDATE que altere coluna
   diferente de `read`/`read_at`. Esta é a rede: mesmo que um endpoint futuro
   tente `notification.update(msg: ...)`, o banco recusa. Notificação é
   quase-append-only, como o log de auditoria (§2.8) — só que com uma janela de
   uma coluna.

*Alternativa descartada:* `attr_readonly` no model + checar `changed_attributes`
num `before_update`. Rejeitada: some no `update_all`, no `import` e no console —
que é onde o auditor vai bater.

*Alternativa descartada:* `REVOKE UPDATE (msg, type, ...) ON notifications`
coluna a coluna, como o `REVOKE` do audit-log (D12). Rejeitada porque o
privilégio de coluna não distingue "a própria" de "de outrem" — a trigger
cobre os dois casos com um mecanismo só.

### D-N5 — Format strings versionadas em locale (D14), não literais

`config/locales/pt-BR.notifications.yml`:

```yaml
pt-BR:
  notifications:
    v1:
      assign:   '%{author} atribuiu você à tarefa "%{task}" (robô %{robot})'
      progress: '%{author} registrou %{n}%% na tarefa "%{task}" (robô %{robot}): %{comment}'
      done:     'Tarefa "%{task}" (robô %{robot}) foi concluída por %{author}'
```

O `v1` é literal e deliberado: as strings são **versionadas**. Se a redação mudar,
entra `v2` e a `v1` fica — porque as notificações já persistidas carregam `msg`
materializada e a suíte de contrato compara contra a versão que gerou. Um
`format_version smallint NOT NULL DEFAULT 1` na tabela registra qual foi usada.

`msg` é **materializada na criação**, não renderizada na leitura. *Alternativa
descartada:* guardar `type` + params JSON e formatar no cliente. Rejeitada: a
invariante 8 é sobre a mensagem (`msg ≤ 500`) e não teria o que limitar; e o
texto deixaria de ser um registro histórico estável.

**Truncamento:** o único campo de tamanho livre é `%{comment}` (avanço limita a
<100 chars por §2.4, mas dado legado pode ser maior). Antes de persistir, se a
`msg` renderizada passar de 500, o **comentário** é truncado com `…` até a `msg`
caber. Nunca a descrição da tarefa, nunca o nome do robô — o contexto de
navegação vale mais que a cauda do comentário. Se ainda assim não couber (desc de
tarefa absurda), a criação falha na CHECK e cai no caminho best-effort (D-N7).

### D-N6 — Destinatários: dedup e "nunca o autor", em conjunto e nessa ordem

Um único ponto de resolução, `Notifications::RecipientResolver`:

1. Monta o conjunto bruto conforme o tipo:
   - `assign` → **apenas o delta** (`novos_assignees − assignees_anteriores`).
     Quem já estava não é re-notificado.
   - `progress` / `done` → **todos** os responsáveis atuais da tarefa.
2. `Set` de `person_id` → dedup estrutural (não por nome — D11 já eliminou a
   colisão de homônimos que o legado tinha).
3. Subtrai `actor_person_id`.
4. Se vazio, **nada é criado**. Zero notificações é um resultado válido, não um
   erro.

Reforço no banco: índice único parcial
`UNIQUE (recipient_person_id, ctx_task_id, type, recorded_at)` para `type =
'assign'`, tornando a re-notificação de atribuição idempotente sob retentativa de
job. *Alternativa descartada:* deixar a dedup só no Ruby. Rejeitada porque o job
é `retry`-ável e Sidekiq entrega ao menos uma vez.

**Progresso `0` não notifica.** A guarda mora no chamador *e* no resolver:
`progress` só dispara para `0 < to < 100`; `to == 100` dispara `done`; `to == 0`
(reset para Pendente/N/A, §2.2) dispara nada. Não é caso especial de
destinatário, é caso especial de evento — e vive numa única função pura testável.

### D-N7 — Best-effort: job Sidekiq **enfileirado após commit**, fora da transação

`NotifyTaskEventJob.perform_later` é chamado de um `after_commit` do avanço/da
atribuição. Consequências deliberadas:

- A transação do save já commitou quando o job existe. **Nenhuma falha de
  notificação pode dar rollback no avanço** — não há transação para derrubar.
- Se o job falhar (Person removida, CHECK violada, Redis fora), o retry do
  Sidekiq tenta; esgotado o retry, vai para a dead set e emite erro estruturado.
  O avanço permanece salvo. É exatamente a semântica "best-effort" de §2.7.
- O job é idempotente por D-N6.

*Alternativa descartada 1:* criar as notificações **na mesma transação** do
avanço. Rejeitada: viola §2.7 diretamente — uma `msg` de 501 chars, um destinatário
com FK quebrada ou um deadlock derrubariam o registro do avanço, que é o dado
que o engenheiro no galpão realmente veio salvar. Perder a notificação é
aceitável; perder o avanço não é.

*Alternativa descartada 2:* síncrono, dentro do request mas fora da transação,
envolto em `rescue => e; Rails.error.report(e); end`. Mais simples e sem
dependência de Redis, mas paga a latência de N inserts no request do avanço —
justamente o request que precisa ser rápido em rede de galpão — e um `rescue`
nu vira o lugar onde falhas somem. Ficou como *fallback documentado* caso o
Sidekiq não esteja disponível no ambiente; a decisão principal é o job.

*Onde mora:* `after_commit` + `sidekiq_options queue: :notifications, retry: 5`.
Exige fila nomeada em produção — `delivery-and-observability`.

### D-N8 — Alerta do SO: "novo" é uma marca d'água do cliente, não `read = false`

O cliente mantém, **em memória** (não em `localStorage`), uma marca d'água:
o maior `recorded_at` visto até agora, inicializada na **primeira** resposta da
lista. Regra:

- A primeira carga da sessão **apenas define a marca d'água**. Dispara zero
  alertas, independentemente de quantas não lidas existirem.
- Alertas só disparam para notificações com `recorded_at > marca_d'água` que
  cheguem **depois** dessa inicialização (via evento de `realtime-collaboration`
  ou polling subsequente). Após disparar, a marca d'água avança.
- `document.visibilityState === 'visible'` suprime o alerta do SO — se a pessoa
  já está olhando o app, o toast in-app basta.
- `Notification.permission !== 'granted'` → nenhum alerta, e nenhuma tentativa.
  A permissão é pedida por **gesto explícito** do usuário no centro de
  notificações, nunca no load — pedir no load é o padrão que faz o Chrome
  bloquear o site permanentemente.

*Alternativa descartada:* disparar para tudo que chegar com `read = false`.
É a implementação óbvia e é o bug: F5 com 10 não lidas antigas = 10 pop-ups.
Este é o modo de falha explícito que a suíte tem que travar.

*Alternativa descartada:* persistir a marca d'água em `localStorage` para
sobreviver ao reload. Rejeitada — e é sutil: com marca d'água persistida, abrir o
app depois de dois dias dispararia alertas de tudo que chegou no intervalo, uma
saraivada. A marca d'água **em memória** dá a semântica certa por construção:
sessão nova = ponto de partida limpo = zero alertas.

*Onde mora:* `useOsNotificationAlerts`, um hook único. Nenhum outro componente
chama `new Notification(...)` — um lint rule (`no-restricted-globals`) proíbe.

### D-N9 — Clique no alerta: `ctx` → rota do robô

`notification.onclick` → `window.focus()` + navegação para
`/ws/:wsId/projects/:pid/cells/:cid/robots/:rid` com `?task=:tid` para destacar a
tarefa. Se `ctx_robot_id` for nulo ou o robô tiver sido excluído, o clique leva ao
centro de notificações com um aviso — nunca a uma tela em branco.

*Onde mora:* a rota é de `app-shell-navigation` / `robot-task-table`; aqui só a
função de mapeamento `ctxToPath(notification)` e seu teste.

### D-N10 — Retenção declarada aqui, executada em outro lugar

`notifications` cresce monotonicamente e **nada a expurga hoje** — é o mesmo
buraco que §2.8 tem no log de auditoria. Política:

- Elegível a expurgo: `read = true AND recorded_at < now() - interval '90 days'`.
- **Não lidas nunca são expurgadas automaticamente**, em nenhuma idade.
- Índice de suporte: `INDEX (workspace_id, read, recorded_at)`.
- Índice de leitura do centro: `INDEX (workspace_id, recipient_person_id,
  recorded_at DESC)`.

O cron/job de expurgo, sua janela e seu alerta de crescimento de tabela são de
**`delivery-and-observability`**. Aqui entregamos a política, os índices e um
scope `Notification.purgeable` testado — para que a outra capacidade não precise
re-derivar a regra.

## Plano de migração

1. Migration única cria enum `notification_type`, tabela, as 4 CHECKs, as 2
   triggers e os 2 índices. Não é destrutiva — tabela nova.
2. Locale `pt-BR.notifications.yml` com o bloco `v1`.
3. `RecipientResolver` + `MessageBuilder` como objetos puros, com teste, **antes**
   do job — são a lógica que erra.
4. Job + `after_commit` nos pontos de `progress-advances` e `robot-tasks`.
5. Endpoints + policy + entrada no route-sweep de D3.
6. Cliente: query key `['ws', wsId, 'notifications']` (D9), centro de
   notificações, e só então o hook de alerta do SO.
7. `legacy-data-migration` importa notificações do export: `target` (nome) é
   resolvido para `recipient_person_id`; linhas cujo nome não resolve, ou cuja
   `msg` passa de 500, são **descartadas com relatório** — notificação histórica
   não vale um import travado. Essa resolução é executada lá, não aqui.

## Risks / Trade-offs

- **A marca d'água em memória perde alertas entre reloads.** Uma notificação que
  chega enquanto a aba está fechada nunca vira alerta do SO. Aceito: ela aparece
  no badge e na lista. Alerta local do SO é para presença, não para entrega
  garantida — isso seria Web Push, que é não-objetivo.
- **`msg` materializada não se corrige.** Se a pessoa mudar de nome, notificações
  antigas mantêm o nome antigo. É o comportamento do legado (`byName` é
  snapshot) e está correto para um registro histórico — mas vai gerar ticket de
  suporte.
- **Truncamento de comentário (D-N5) apaga informação** na notificação. Mitigado:
  a `msg` completa está no avanço, a um clique de distância via `ctx`.
- **Dependência de Redis para o caminho de notificação.** Redis fora = nenhuma
  notificação, silenciosamente (avanços seguem salvando, corretamente). Precisa de
  alerta de fila parada — `delivery-and-observability`.
- **`ts_local` é dado morto para o app novo.** Carregado só por fidelidade a §1.1
  e pelo importador. Se `legacy-data-migration` decidir descartá-lo, a coluna vira
  candidata a remoção.

## Perguntas em aberto

1. Notificação `assign` deve ser criada quando alguém é auto-atribuído por §2.3
   (o autor entra sozinho na tarefa)? Pela regra "nunca notifica o autor", não —
   e é o que implementamos. Confirmar com produto que não há caso em que o
   auto-atribuído queira o registro.
2. Um membro removido do workspace mantém as notificações? Hoje a `Person`
   sobrevive à remoção da `Membership` (D10), então as notificações também
   sobrevivem — mas a RLS as torna inalcançáveis. Confirmar se devem ser
   expurgadas na remoção.
3. Retenção de 90 dias é chute calibrado por "um comissionamento dura um
   trimestre". Validar com o dono do produto antes de o expurgo entrar em
   produção.
