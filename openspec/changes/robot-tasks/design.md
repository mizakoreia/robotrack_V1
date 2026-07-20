## Context

A Tarefa (§1.1) era um objeto dentro do array `tasks` do documento do Robô, que
por sua vez estava dentro do array `robots` da Célula, dentro do array `cells` do
Projeto. Uma única escrita reescrevia o documento inteiro do projeto. Isso dava
atomicidade grátis e concorrência péssima: dois engenheiros no mesmo projeto
sobrescreviam-se mutuamente e a última escrita vencia sem aviso.

Três consequências desse formato precisam ser traduzidas conscientemente:

1. **Ordem era posição no array.** No relacional vira coluna `position` explícita.
2. **Responsável era nome.** `assignees: ["João Silva"]`, mais o campo legado
   `resp` (string única), mais o sentinela `"Não Atribuído"` como valor
   legítimo. Isso é o que **D10**/**D11** abolem.
3. **Não havia controle de concorrência.** No alvo, `lock_version` na tarefa.

O legado também tinha uma regra de escrita retroativa (§1.4 item 1, última
frase): ao gravar `assignees`, gravar também `resp = assignees[0] || "Não
Atribuído"`. O plano anterior deixou isso como um condicional não resolvido —
"apenas se a interoperabilidade com dados antigos for exigida" — sem dono e sem
tarefa de decisão. Isso contradiz frontalmente a regra "nenhum nome como chave".
Este documento resolve o condicional (D-RT-2).

## Goals / Non-Goals

**Goals**

- Esquema relacional de `tasks` que suporte criação offline (uuid do cliente),
  isolamento por tenant no banco e concorrência otimista.
- Atribuição exclusivamente por `people.id`, com ausência = conjunto vazio.
- Criação em lote de §2.5 determinística: mesmo input → mesmo conjunto de robôs
  e tarefas, incluindo os casos de clamp e dedup.
- CRUD de tarefa avulsa e substituição do conjunto de responsáveis.

**Non-Goals**

- Nenhuma mutação de `progress`/`status` por esta capacidade (é
  `progress-advances`). Os endpoints daqui **rejeitam** esses campos no payload.
- Nenhum cálculo consolidado (é `progress-rollup`).
- Nenhuma renderização (é `robot-task-table`).
- Nenhuma leitura de export Firestore (é `legacy-data-migration`).

## Decisions

### D-RT-1 — `task_assignees` é tabela de junção por `person_id`, não array

`task_assignees(id uuid PK, workspace_id uuid NOT NULL, task_id uuid NOT NULL,
person_id uuid NOT NULL, created_at)`.

**Onde a invariante mora:**
- Unicidade: **índice único** `(task_id, person_id)` — não `validates uniqueness`,
  que perde para corrida entre duas requisições.
- Coerência de tenant: FKs **compostas** `(task_id, workspace_id) REFERENCES
  tasks(id, workspace_id)` e `(person_id, workspace_id) REFERENCES
  people(id, workspace_id)`, o que exige índice único `(id, workspace_id)` em
  ambas as tabelas-pai. Isso torna **impossível no banco** atribuir uma pessoa do
  workspace A a uma tarefa do workspace B, mesmo por console.
- Isolamento de leitura: **RLS** com `app.current_workspace_id` (**D2**).
- `ON DELETE CASCADE` a partir de `tasks`; a partir de `people`, `RESTRICT` —
  remover uma pessoa com atribuições é decisão de `workspace-tenancy`, não um
  apagamento silencioso aqui.

**Alternativa descartada:** coluna `assignee_person_ids uuid[]` no `tasks` (mais
próxima do legado, uma leitura a menos). Descartada porque: (a) não há como
expressar FK por elemento de array em Postgres, então a integridade referencial
voltaria a viver no model; (b) "Minhas Tarefas" (§3.6) e as notificações (§2.7)
viram `= ANY(...)` sobre array, que não usa índice tão bem quanto um join com
índice em `(person_id, task_id)`; (c) remoção de pessoa não teria `RESTRICT`.

**Alternativa descartada:** manter lista de nomes com uma tabela `responsibles`
de strings no workspace (o que o legado fazia). Descartada por D10/D11 — nome não
é identidade.

### D-RT-2 — O esquema novo NÃO tem `resp`; a leitura tolerante é do importador

**Decisão explícita, resolvendo o condicional pendente do plano anterior:**

- `tasks` **não** tem coluna `resp`. Não existe grafia de compatibilidade.
- Nenhum service desta capacidade executa `resp = assignees[0] || "Não Atribuído"`.
- A leitura tolerante de §1.4 item 1 (se `assignees` existe use-o; senão se `resp`
  existe e ≠ `"Não Atribuído"` trate como `[resp]`; senão vazio) é implementada
  **uma única vez**, no importador de `legacy-data-migration`, sobre o JSON de
  export — nunca sobre uma linha do Postgres.

**Justificativa.** A regra de escrita do legado existia para manter um *leitor
antigo* funcionando durante a transição do PWA. Aqui não há leitor antigo: o
Firestore é desligado na migração, é um corte único e não uma sincronização
bidirecional. Manter `resp` significaria: (a) reintroduzir um nome como chave
dentro do esquema que D11 acabou de limpar; (b) criar um segundo caminho de
verdade sobre quem é responsável, que divergiria do join na primeira atribuição
múltipla; (c) ressuscitar `"Não Atribuído"` como valor persistido, quebrando o
filtro de §3.6 e a dedup de destinatários de §2.7. O custo de não manter é zero,
porque nada além do importador lê `resp`.

**Alternativa descartada:** manter `resp` como coluna gerada
(`GENERATED ALWAYS AS`) para leitura legada. Descartada porque uma coluna gerada
precisaria de um nome — ou seja, um join e um `ORDER BY` arbitrário para eleger o
"primeiro" responsável — e o legado não define ordem estável em `assignees`; o
valor seria não determinístico.

**Consequência para `legacy-data-migration` (dependência declarada, não
implementada aqui):** o importador resolve nome → `Person` (casando por nome
normalizado dentro do workspace, criando `Person` com `user_id` nulo quando não
houver correspondência), descarta `"Não Atribuído"` (**D11**) e insere linhas em
`task_assignees`. Se um nome legado não resolver para nenhuma pessoa, a tarefa
fica com conjunto vazio — nunca com uma `Person` chamada `"Não Atribuído"`.

### D-RT-3 — `progress` e `status` são colunas com constraint, mas read-only aqui

`progress smallint NOT NULL DEFAULT 0 CHECK (progress BETWEEN 0 AND 100)`,
`status` como **enum Postgres** `task_status` com os quatro valores exatos em
pt-BR (`Pendente`, `Em Andamento`, `Concluído`, `N/A`) — os mesmos literais que a
spec usa, para não haver tradução na fronteira.

**Onde a invariante mora:** `CHECK` para a faixa, tipo `ENUM` para o domínio de
status. O acoplamento §2.2 entre os dois (`status='Concluído'` ⇒ `progress=100`
etc.) **não** é constraint aqui, porque `Em Andamento` admite qualquer progresso
e `N/A` admite 0 apenas por convenção de transição — expressá-lo como CHECK
travaria a migração de dados legados sujos. Ele vive na máquina de estados de
`progress-advances`, que é sua dona.

**Alternativa descartada:** `status` como string livre com validação no model.
Descartada — model se contorna por console e o legado já provou que status livre
gera variantes ("Concluido" sem acento) que quebram o rollup.

Os endpoints desta capacidade (`PATCH /tasks/:id` para descrição) **rejeitam com
422** qualquer payload contendo `progress` ou `status`. Alterá-los é
exclusivamente pelo endpoint de avanço de `progress-advances`.

### D-RT-4 — Criação em lote é uma transação, com clamp e dedup no servidor

O assistente é UI de dois passos, mas a chamada é **uma única** requisição
`POST /api/v1/cells/:cell_id/robots/batch` com
`{application, robots: [{id, name}, ...]}` — os uuids vêm do cliente (**D1**).

Normalização, **no servidor** (a UI repete por conveniência, não por segurança):
1. `trim` em cada nome; descartar vazios.
2. Deduplicar por nome normalizado (`trim` + colapso de espaços internos +
   casefold Unicode), preservando a **primeira** ocorrência.
3. Clamp da contagem resultante em 50; excedente é **descartado**, não erro.

Se após a normalização a lista fica vazia, resposta **422** — criar zero robôs
silenciosamente seria indistinguível de sucesso para a fila offline.

**Onde a invariante mora:** o clamp de 1–50 é do *service*, não do banco; é regra
de UX de leva, não de integridade (nada impede um robô ser criado avulso, e um
robô de outra leva não conflita). A dedup **dentro da leva** também é do service:
o legado permite dois robôs homônimos em levas diferentes na mesma célula, e um
índice único `(cell_id, name)` mudaria esse comportamento. Já a coerência de
tenant e a ordem (`position`) são de `commissioning-hierarchy`.

**Alternativa descartada:** N requisições `POST /robots`, uma por robô, deixando
o cliente deduplicar. Descartada porque perde a atomicidade (uma leva
parcialmente criada é lixo que o usuário tem que limpar à mão) e porque a fila
offline (**D7**) teria de reordenar N mutations dependentes em vez de uma.

### D-RT-5 — Materialização das tarefas-base é cópia por valor, no momento da criação

Cada robô da leva recebe **cópias** dos `task_templates` que passam no filtro de
§2.5 (regra definida por `task-catalog`: `appFilters` vazio **OU** contém
`"Misto / Geral"` **OU** contém `"Todas"` **OU** contém a Aplicação do robô).
Copiam-se `cat`, `desc`, `weight`. `progress = 0`, `status = 'Pendente'`,
nenhuma linha em `task_assignees`.

`position` é atribuída pela ordem lexicográfica de `(cat, desc)` — o prefixo
alfabético das categorias (`A.`, `B.`, …) é o que ordena na tela (§1.3), e
congelar essa ordem na criação evita que o agrupamento dependa de um `ORDER BY`
implícito na leitura.

**Não há `template_id` na tarefa.** Editar um template depois **não** altera
tarefas já criadas — é isso que §2.6 (sincronização retroativa, de `task-catalog`)
existe para resolver, e ela casa por `desc`, não por id.

**Alternativa descartada:** referência `task_templates.id` na tarefa, com os
campos lidos por join. Descartada porque tornaria a edição de um template uma
reescrita retroativa de histórico de robôs já comissionados — e porque §2.6
explicitamente casa por `desc` e "nunca sobrescreve", o que só faz sentido se a
cópia for por valor.

Inserção com `insert_all` em lote único (50 robôs × ~31 templates ≈ 1550 linhas)
dentro da mesma transação da criação dos robôs.

### D-RT-6 — Substituição de responsáveis é PUT idempotente do conjunto

`PUT /api/v1/tasks/:id/assignees` com `{person_ids: [...]}` substitui o conjunto
inteiro (diff calculado no servidor: insert dos entrantes, delete dos que saíram).

**Por quê PUT de conjunto e não POST/DELETE por item:** o modal de §3.5 é uma
lista de checkboxes — o usuário confirma um estado, não uma sequência de deltas.
Reenviar o mesmo PUT (retry da fila offline, **D7**) é inócuo. Com POST/DELETE
por item, um retry duplicaria ou desfaria.

O **diff é o que `in-app-notifications` consome**: só quem *entrou agora* recebe
notificação `assign` (§2.7) — quem já estava não é re-notificado. O service desta
capacidade retorna `{added: [...], removed: [...]}` e publica o evento; a decisão
de notificar é da outra capacidade.

`person_ids` vazio é válido e significa "sem responsável" (**D11**). Um
`person_id` de outro workspace resulta em **404**, não 403 — não vazamos a
existência do recurso (**§4.1 inv. 1**).

**Cadastrar pessoa nova no modal:** o cliente cria a `Person` primeiro
(`POST /people`, de `workspace-tenancy`, com uuid gerado no cliente) e em seguida
inclui esse id no PUT. Duas chamadas, ordenáveis pela fila offline. **Alternativa
descartada:** aceitar `new_person_names: [...]` no próprio PUT — descartada
porque reintroduziria nome como entrada de um endpoint de atribuição, exatamente
o acoplamento que D11 remove, e porque a criação de pessoa tem regra própria
(casamento por e-mail) que não pertence aqui.

### D-RT-7 — Concorrência: `lock_version` na tarefa, 409 no conflito

`lock_version integer NOT NULL DEFAULT 0`, optimistic locking do ActiveRecord.
Editar descrição ou trocar responsáveis exige `lock_version` no payload;
divergência → **409** com o estado atual no corpo, para o cliente reconciliar.

Isto substitui o "última escrita vence" do documento-inteiro do Firestore, mas
com granularidade de **tarefa**, não de projeto: dois engenheiros em tarefas
diferentes do mesmo robô nunca conflitam.

**Alternativa descartada:** `updated_at` como token de versão. Descartada porque
duas escritas no mesmo milissegundo não são distinguíveis e porque a fila offline
(**D7**) reenvia mutations com timestamp antigo.

### D-RT-8 — Autorização: policy declarada, negação server-side

Toda ação desta capacidade declara `TaskPolicy` / `RobotBatchPolicy` (**D3**).
Criar/editar/excluir tarefa, criar robôs em lote e atribuir responsáveis exigem
papel `owner` ou `edit` (§4.1). Membro `view` recebe **403** (**§4.1 inv. 4** — a
única mutação de um `view` é marcar a própria notificação como lida).

Recurso de outro workspace: **404**, garantido por RLS antes da policy — a query
simplesmente não retorna a linha. A policy é a segunda camada, não a única.

## Plano de migração

1. Migration A: `CREATE TYPE task_status`, tabela `tasks`, índice único
   `(id, workspace_id)`, índice `(robot_id, position)`, RLS `ENABLE` + `FORCE` e
   policy usando `current_setting('app.current_workspace_id')`.
2. Migration B: tabela `task_assignees` com as FKs compostas, índice único
   `(task_id, person_id)`, índice `(person_id, task_id)` para §3.6, RLS.
3. Ambas são **aditivas**; não há tabela pré-existente a alterar (nada foi
   construído). Nenhuma etapa destrutiva nesta capacidade.
4. `commissioning-hierarchy` precisa ter criado `robots` com índice único
   `(id, workspace_id)` — se não tiver, a FK composta de `tasks` falha. Aresta
   explícita, verificada na tarefa 1.5.

## Riscos / Trade-offs

- **Transação longa no lote máximo.** 50 robôs × 31 tarefas + 50 linhas de robô
  em uma transação. Mitigação: `insert_all` (não `create!` em loop), medição com
  dataset de carga e alerta de duração — coordenar com
  `delivery-and-observability`. Risco aceito porque a alternativa (lote assíncrono
  via Sidekiq) devolveria ao usuário uma tela sem robôs e quebraria a expectativa
  de §2.5, que é síncrona.
- **RLS + `insert_all`.** `insert_all` ignora callbacks do model, então
  `workspace_id` tem de ser montado explicitamente em cada hash. Se esquecido, a
  policy de RLS rejeita o INSERT — falha ruidosa, que é o comportamento desejado.
  Coberto por teste negativo.
- **`RESTRICT` em `people`.** Remover do workspace uma pessoa com tarefas
  atribuídas vai falhar. É intencional (não queremos atribuição órfã), mas
  `workspace-tenancy` precisa oferecer um caminho de desatribuição em massa. Está
  registrado como pergunta em aberto abaixo.
- **Ordem `position` congelada na criação.** Se `task-catalog` renomear a
  categoria de um template depois, robôs antigos mantêm a ordem antiga. Aceito:
  o alvo é estabilidade de tela, e §2.6 já é o mecanismo de retroatividade.
- **Duas chamadas para "cadastrar pessoa nova e atribuir".** Se a segunda falhar,
  fica uma `Person` criada e não atribuída. Aceito: uma pessoa a mais no
  workspace é ruído recuperável; uma atribuição a uma pessoa inexistente não é.

## Perguntas em aberto

1. **Remoção de pessoa com atribuições** — `workspace-tenancy` faz soft-delete da
   `Person` (mantendo atribuições) ou exige desatribuir antes? Esta capacidade
   assume `RESTRICT` até haver decisão. **Dono: `workspace-tenancy`.**
2. **Excluir uma tarefa com histórico de avanços** — `progress-advances` decide se
   `task_advances` cascateia ou se a exclusão vira soft-delete. Esta capacidade
   implementa hard delete de `tasks`; se a decisão for soft-delete, a coluna
   entra numa migration aditiva de `progress-advances`. **Dono:
   `progress-advances`.**
3. **Limite superior de tarefas por robô** — o legado não tinha. Não introduzimos
   um; se o dataset de carga de `quality-and-accessibility` mostrar degradação da
   tabela acima de N tarefas, revisitar.
