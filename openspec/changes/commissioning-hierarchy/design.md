## Context

O legado guarda `Projeto → Célula → Robô → Tarefa` como **um único documento Firestore
por projeto**, com células, robôs e tarefas como arrays aninhados (§1.1). Consequências
que o porte herda como sintomas e precisa curar na origem:

- **Ordem manual tem duas representações** (§2.9): projeto persiste `_ord` inteiro, mas
  *inicializado com timestamp* na criação; célula e robô não persistem ordem nenhuma —
  ordem é a posição no array. Duas representações, uma delas com semântica dupla
  (timestamp e índice no mesmo campo).
- **Identidade é do servidor.** No Firestore o cliente gera id localmente e por isso o
  offline do legado funciona. Num porte ingênuo para Rails, `id` viria do `INSERT` — e
  §4.2 ("escritas resolvem localmente e são reenviadas") deixaria de ser implementável.
- **Leitura é tolerante por necessidade** (§1.4): documentos antigos vêm sem `cells`,
  sem `robots` ou sem `tasks`, e o render nunca pode quebrar.
- **Autorização morava em `firestore.rules`**, ou seja, no perímetro do banco. Ao portar,
  a tentação é mover tudo para o model Ruby. Isso é regressão de garantia: um `rails c`
  contorna um model, não contorna uma constraint nem RLS.

Esta mudança está na Onda 3, depende de `authorization-policies` (que depende de
`workspace-tenancy`) e é a primeira coisa do domínio RoboTrack a existir no banco. Por
isso ela é dona de D1 e D13 — todo esquema posterior copia o que for decidido aqui.

## Goals / Non-Goals

**Goals**

1. Três tabelas relacionais equivalentes às três entidades de §1.1, com `_updatedBy` /
   `_updatedAt` nos três níveis (o legado só tinha no projeto).
2. PK `uuid` gerável no cliente, com semântica de replay definida — a pré-condição de D7.
3. Uma representação única de ordem manual, cobrindo os três níveis (§2.9).
4. Isolamento de tenant garantido por **constraint + RLS**, não por convenção de model.
5. `progress_cache` presente na migration de origem (D5), com default que já satisfaz a
   leitura tolerante de §1.4.
6. CRUD que uma tela de §3.3/§3.4 possa chamar sem inventar contrato.

**Non-Goals**

- Layout e hubs de §3.3/§3.4 (`hierarchy-screens`), semântica de progresso
  (`progress-rollup`), `tasks` e lote §2.5 (`robot-tasks`), fila offline (`offline-pwa`),
  matriz de papéis (`authorization-policies`), importador (`legacy-data-migration`).
- Soft delete / lixeira. Exclusão é física e cascateada (ver D-H6).
- Mover uma célula entre projetos ou um robô entre células. Não está em §3.3/§3.4 e o
  esquema abaixo (FK composta) suporta adicioná-lo depois sem migration de dados.

## Decisions

### D-H1 — PK `uuid` em toda tabela de domínio, com valor aceito do cliente (dono de D1, D13)

```sql
id uuid PRIMARY KEY DEFAULT gen_random_uuid()
```

O `POST` aceita `id` no corpo. Se ausente, o banco gera. **Onde mora a invariante:**
default no banco (não `before_create` no model) + validação de formato no endpoint +
`PRIMARY KEY` para colisão.

Regras de aceitação do id fornecido, na service:

- Precisa casar `^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$`
  (UUID v1–v8, variante RFC 4122). Qualquer outra coisa → `422`.
- O UUID nulo (`00000000-...`) é rejeitado explicitamente — é o valor que um cliente com
  bug ou um `parseInt` mal feito produz, e ele passaria numa checagem de formato frouxa.

**Alternativa descartada:** `bigserial` com uma coluna `client_generated_id` só em
`task_advances` (o que o plano anterior fez). Descartada porque torna a criação offline
de robô **estruturalmente impossível**: sem id de servidor para o robô, não existe alvo
para as tarefas dele, e sem tarefas não há como enfileirar avanço — a fila de D7 nunca
consegue ordenar dependências entre itens que ainda não têm identidade. O `client_id`
pontual resolve dedup de um POST, não resolve grafo de dependência.

**Alternativa descartada:** ULID/`uuid v7` em coluna `text`. Ordenação temporal seria
boa para índice, mas `text` perde a validação de tipo do Postgres e obriga cast em toda
FK. Se a locality de índice virar problema medido, migra-se o *default* para `uuid_generate_v7()`
sem trocar o tipo da coluna nem uma linha de aplicação — a decisão é reversível de graça.

### D-H2 — Idempotência: replay devolve `200`, colisão real devolve `409`, id de outro tenant devolve `404`

Cliente offline reenvia. O `INSERT` é feito com `ON CONFLICT (id) DO NOTHING RETURNING *`;
se nada volta, a service busca a linha e decide:

| Situação | Resposta |
|---|---|
| id existe, mesmo `workspace_id`, mesmo escopo pai e mesmo `name` | `200` com o recurso existente (replay idempotente) |
| id existe, mesmo `workspace_id`, mas `name` ou pai diferentes | `409` com o recurso atual no corpo, para o cliente reconciliar |
| id existe em **outro** `workspace_id` | `404` |
| id não existe | `201` |

O `404` do terceiro caso é deliberado: um `409` confirmaria a existência de um id de
outro tenant e transformaria a PK num oráculo de enumeração. Na prática RLS já esconde a
linha, então a service **não consegue** distinguir "existe em outro tenant" de "não
existe" — e o `INSERT` falha com violação de PK vinda do banco, que é traduzida em `404`.
Isso é a garantia, não uma checagem de aplicação.

**Alternativa descartada:** header `Idempotency-Key` com tabela de chaves e TTL. É o
padrão para POST sem id natural; aqui o id **é** a chave de idempotência, e uma tabela
extra com expiração criaria uma janela em que o replay tardio de um cliente que ficou
uma semana offline vira duplicata.

### D-H3 — `position`: uma coluna inteira, contígua, 0-based, por escopo

`_ord` e "posição no array" viram `position integer NOT NULL`, com escopo:

| Tabela | Escopo da ordem |
|---|---|
| `projects` | `workspace_id` |
| `cells` | `project_id` |
| `robots` | `cell_id` |

**Onde mora a invariante:** índice único
`(escopo, position) DEFERRABLE INITIALLY DEFERRED`. O `DEFERRABLE` é o que permite
renumerar N linhas dentro de uma transação sem passar por posições temporárias fake
(`position = -1`, ou renumerar começando do fim). A contiguidade (0..n-1, sem buracos) é
verificada por um spec de invariante sobre o esquema, não por trigger — trigger de
contiguidade dispararia por linha e brigaria com o próprio update em lote.

Reordenar renumera **todo o escopo** numa transação com `SELECT ... FOR UPDATE` na linha
pai (o projeto, para células; a célula, para robôs; o workspace, para projetos). Custo
O(n) por reordenação, com n = número de irmãos.

**Alternativa descartada:** posição fracionária (float médio entre vizinhos, ou LexoRank).
Ganho real seria O(1) por movimento, mas custa: drift de precisão de `double` após ~50
inserções no mesmo intervalo, necessidade de um job de rebalanceamento, e ordem que deixa
de ser legível/diffável em log de auditoria. O ganho não se paga na cardinalidade real —
dezenas de projetos por workspace, dezenas de células por projeto, e §2.5 limita robôs a
lotes de 50. Se um workspace passar de ~1.000 irmãos num escopo, revisitar.

**Alternativa descartada:** manter `_ord` como timestamp na criação (o legado). Mistura
duas semânticas na mesma coluna, torna "inserir no meio" impossível sem reescrever tudo
mesmo assim, e faz o índice único de contiguidade ser inexprimível.

Item novo entra em `position = COALESCE(MAX(position) + 1, 0)` do escopo, calculado
dentro da mesma transação do `INSERT`, sob o mesmo lock do pai.

### D-H4 — Reordenação em lote com detecção de conflito por conjunto de ids

`PATCH /api/v1/projects/reorder` (e equivalentes por escopo) recebe:

```json
{ "scope_id": "<uuid do pai>", "ordered_ids": ["<uuid>", "<uuid>", ...] }
```

A service compara `ordered_ids` (como conjunto) com os ids atualmente no escopo:

- conjuntos iguais → renumera 0..n-1 e responde `200` com a lista final.
- conjuntos diferentes (alguém criou, excluiu ou moveu um irmão entre o carregamento da
  tela e o drop) → `409` com o conjunto atual, sem escrever nada. O cliente recarrega e
  o usuário refaz o arrasto.

**Onde mora a invariante:** transação + `FOR UPDATE` no pai serializa reordenações
concorrentes; a comparação de conjuntos é a checagem semântica em cima disso.

**Alternativa descartada:** `PATCH` por item (`{id, position}`), como o drag&drop do
legado fazia gravando item a item. Não é atômico: uma perda de rede no meio deixa a
lista com posições duplicadas ou com buraco, e o índice único então rejeita a *próxima*
escrita legítima do usuário — falha que aparece longe da causa.

**Alternativa descartada:** usar `lock_version` do pai para conflito de ordem. Não serve:
renomear um projeto incrementaria `lock_version` e invalidaria uma reordenação que não
conflita com nada. Conjunto de ids é a condição precisa.

### D-H5 — `workspace_id` desnormalizado, `NOT NULL`, com FK composta e RLS (implementa D2)

As três tabelas carregam `workspace_id uuid NOT NULL REFERENCES workspaces(id)`. A
desnormalização não é atalho de performance — é o que permite que a política RLS seja
uma comparação de coluna local em qualquer nível, sem join até o projeto.

O risco óbvio da desnormalização é divergência (uma célula com `workspace_id` diferente
do projeto dela). **Onde mora a invariante:**

```sql
-- em projects e cells
UNIQUE (id, workspace_id)
-- em cells
FOREIGN KEY (project_id, workspace_id) REFERENCES projects (id, workspace_id) ON DELETE CASCADE
-- em robots
FOREIGN KEY (cell_id, workspace_id) REFERENCES cells (id, workspace_id) ON DELETE CASCADE
```

A FK composta torna a divergência **impossível de representar**, não apenas improvável.
Um `UPDATE` de console que trocasse o `workspace_id` de uma célula sem trocar o do
projeto seria rejeitado pelo banco.

RLS por tabela:

```sql
ALTER TABLE projects ENABLE ROW LEVEL SECURITY;
ALTER TABLE projects FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON projects USING (
  workspace_id = current_setting('app.current_workspace_id', true)::uuid
);
```

`FORCE` é necessário porque o dono da tabela ignora RLS por padrão — sem ele a política
não vale para o usuário de migration/console. O `current_setting(..., true)` com sessão
sem a variável setada retorna `NULL`, o predicado vira `NULL` e **nenhuma linha é
visível** — o fail-closed correto. Setar a variável por request é de `workspace-tenancy`;
escrever estas três políticas é desta mudança.

**Alternativa descartada:** só `default_scope` no model. Um console, um job Sidekiq que
esqueceu o `Current.workspace`, ou um `unscoped` num relatório vazam o tenant inteiro.
RLS torna o vazamento um erro de banco.

### D-H6 — Exclusão física, cascade explícito e o que **não** cascateia

Excluir é `DELETE` de verdade (§3.3 "renomear/excluir célula"), não soft delete.

Cascateia por FK do banco: `projects → cells → robots → tasks → (task_advances,
task_assignees)`. As FKs de `tasks` para baixo são declaradas por `robot-tasks` e
`progress-advances`; esta mudança declara as duas primeiras arestas e **exige** por
contrato que as de baixo sejam `ON DELETE CASCADE`, com um spec de esquema que falha se
alguma vier `RESTRICT` ou `SET NULL`.

**Não cascateia, deliberadamente:**

- `audit_logs` — append-only com `REVOKE UPDATE, DELETE` (D12). O log de que o robô
  existiu sobrevive ao robô. FK para robô: **não existe**; o log guarda o texto (§2.8) e
  o id como valor solto, não como referência.
- `notifications` — o `ctx {pid, cid, rid, tid}` (§1.1) é ponteiro de navegação, não FK.
  Navegar para um alvo excluído cai no tratamento de "não encontrado" de
  `in-app-notifications`, não em erro de FK.
- `people` / `memberships` — `updated_by_person_id` é `ON DELETE SET NULL`. Remover um
  membro do workspace não pode apagar projetos.

Antes de qualquer `DELETE`, a service grava a entrada de auditoria (§2.8) **na mesma
transação**. Se a auditoria falha, a exclusão não acontece.

### D-H7 — `progress_cache` nasce nas migrations de origem (implementa D5)

Nas três tabelas:

```sql
progress_cache jsonb NOT NULL DEFAULT '{}'::jsonb,
progress_cached_at timestamptz
```

Esta mudança é dona de **a coluna existir, ser `NOT NULL` e ter default `'{}'`**;
`progress-rollup` é dona do que vai dentro (as duas métricas de D15: ponderada §2.1 e
contagem crua §3.2) e do job de reconciliação.

O default `'{}'` não é decoração: ele é a versão de §1.4 aplicada ao cache. Uma linha
recém-criada, ou criada offline e sincronizada antes de qualquer cálculo, tem cache
vazio — e a entidade da API traduz vazio em `{weighted: 0, done: 0, total: 0}`. **A tela
nunca recebe `null` e nunca precisa saber que existe cache.**

**Alternativa descartada:** adicionar a coluna na onda de `progress-rollup`. Foi o que o
plano anterior fez, e obriga a retrofitar três migrations já aplicadas em produção — três
`ALTER TABLE` extras, três backfills e uma janela em que a coluna é nullable e todo
consumidor precisa tratar `nil`.

**Alternativa descartada:** view materializada. Refresh é global e grosseiro demais para
um sistema onde a colaboração ao vivo (D6) exige que o anel de progresso reflita o avanço
de outra pessoa em segundos.

### D-H8 — Nome único por escopo, case-insensitive

Índice único `(escopo, lower(name))`. Duas células "Solda 01" no mesmo projeto são erro
de digitação, não intenção; §2.5 já exige dedup na criação de robôs em lote, e é
incoerente deduplicar no lote e permitir duplicata na criação avulsa. `name` também
recebe `CHECK (length(btrim(name)) BETWEEN 1 AND 120)` — nome só de espaços é o caso que
o legado deixava passar e que produz card sem rótulo na grade de §3.3.

**Alternativa descartada:** unicidade só no model (`validates :name, uniqueness:`). Sofre
race entre dois `POST` simultâneos — exatamente o cenário do lote de §2.5 e de dois
clientes offline sincronizando ao mesmo tempo.

### D-H9 — `lock_version` nos três níveis

`lock_version integer NOT NULL DEFAULT 0`, o nome que o Rails reconhece nativamente. Vale
para renomear e para qualquer edição de campo escalar. `409` com o recurso atual no corpo
quando o `UPDATE ... WHERE lock_version = ?` não afeta linha.

Não vale para reordenação (ver D-H4) nem para `progress_cache`: o cache é escrito por job
e por trigger de rollup, e um bump de `lock_version` a cada recálculo faria a tela do
usuário conflitar com o progresso de outra pessoa — que é precisamente a colaboração que
D6 quer preservar. `progress_cache` e `progress_cached_at` são atualizados por `UPDATE`
direto que **não** toca `lock_version`.

### D-H10 — `application` como enum fechado com constraint

`application text NOT NULL DEFAULT 'Misto / Geral'` +
`CHECK (application IN ('Misto / Geral','Solda Ponto','Solda MIG','Handling','Sealing','Outros'))`
(§1.2). O valor é a **string pt-BR literal da spec**, porque ela é a chave de junção com
`appFilters` do catálogo (§1.3) e com o export legado (§1.4 item 3) — traduzir para um
símbolo em inglês exigiria um mapa de ida e volta em três lugares (importador, filtro de
template, relatório) e cada um seria uma chance de divergir.

**Alternativa descartada:** `CREATE TYPE ... AS ENUM`. Adicionar valor a um enum Postgres
não é reversível dentro de uma migration transacional, e §1.2 pode ganhar uma aplicação.
`CHECK` é alterável por `DROP CONSTRAINT` / `ADD CONSTRAINT` em migration reversível.

### D-H11 — Leitura tolerante é do servidor, não da tela (§1.4)

A entidade Grape emite sempre coleção, nunca `null`: projeto sem célula → `"cells": []`;
célula sem robô → `"robots": []`; robô sem tarefa → `"tasks": []` e `"tasks_count": 0`.
O `GET` de coleção vazia é `200` com `[]`, nunca `404`. **Onde mora a invariante:** um
spec de entity que representa uma raiz sem filhos e falha se qualquer chave de coleção
sair `null`. A tela de `hierarchy-screens` decide o estado vazio visual; ela nunca decide
se `null` significa vazio.

## Riscos / Trade-offs

- **Reordenação O(n) por escopo.** Aceito conscientemente (D-H3). Gatilho para revisitar:
  qualquer escopo passando de ~1.000 irmãos, ou p95 de `PATCH /reorder` acima de 300ms.
- **Id do cliente permite forjar identidade.** Um cliente malicioso pode escolher o
  `uuid`. Isso é inofensivo: `workspace_id` vem da sessão, nunca do corpo, e RLS impede
  escrever ou ler fora do tenant. O pior caso é colidir consigo mesmo, que cai em D-H2.
  O que **não** é aceitável e precisa de teste negativo: aceitar `workspace_id` do corpo.
- **`FORCE ROW LEVEL SECURITY` quebra tarefas de manutenção** que legitimamente cruzam
  workspaces (backfill, job de reconciliação de D5). Mitigação: um role dedicado com
  `BYPASSRLS` usado **só** por essas tarefas, nunca pelo processo web. Isso precisa
  existir no ambiente — dependência de `delivery-and-observability`.
- **FK composta engessa "mover célula entre projetos".** Mover exigiria atualizar
  `project_id` e `workspace_id` juntos — o que é justamente correto, já que mover entre
  workspaces deve ser proibido. Custo real: zero hoje; a operação nem está em §3.3.
- **`lock_version` fora da reordenação** significa que renomear e reordenar podem se
  cruzar sem conflito. É o comportamento desejado (§2.9 e §3.3 são ações independentes),
  mas o cliente precisa invalidar as duas query keys — responsabilidade de D6/D9.
- **Escopo grande.** `tasks` ficou fora de propósito, mas isso deixa `robots` sem
  consumidor real até `robot-tasks`. Mitigação: `tasks_count` e `progress_cache` já saem
  na entidade com valor neutro, então `hierarchy-screens` pode ser construída em paralelo
  contra dados vazios.

## Plano de migração

Não há dados em produção — o repositório está em porte. As três migrations são puramente
aditivas e reversíveis (`down` = `drop_table` na ordem inversa). Mesmo assim:

1. `pgcrypto` habilitada por migration própria, **antes** das três, e verificada em
   `db/seeds` — sem ela `gen_random_uuid()` não existe e a migration falha no meio.
2. Ordem obrigatória: `projects` → `cells` → `robots`, por causa das FKs compostas.
3. Índices únicos criados na mesma migration da tabela (base vazia, `CONCURRENTLY`
   desnecessário e incompatível com migration transacional).
4. RLS habilitada na mesma migration da tabela. Habilitar depois cria uma janela em que
   a tabela existe sem isolamento — e é exatamente a janela em que alguém roda um seed.
5. Para `legacy-data-migration`: o importador **preserva** os ids do export Firestore
   quando forem UUID válido, e gera novo `uuid` determinístico (UUIDv5 sobre o id legado)
   quando não forem. `position` é atribuída pela ordem de leitura do array legado, não
   pelo `_ord`-timestamp — que é descartado.

## Perguntas em aberto

1. **Limite de irmãos por escopo.** §2.5 limita robôs a 50 por lote, mas não limita o
   total por célula. Vale um `CHECK` por contagem (via trigger) ou fica como orçamento de
   performance de `quality-and-accessibility`? Proposta: não travar no banco; medir.
2. **Renomear projeto reordena?** Se `hierarchy-screens` oferecer ordenação alfabética
   como alternativa ao manual, `position` continua sendo a fonte, e alfabético vira
   ordenação de leitura. Confirmar com `hierarchy-screens` antes de expor o toggle.
3. **`updated_by_person_id` em cascade de rollup.** Quando o `progress_cache` de um
   projeto muda por causa de um avanço de outra pessoa num robô, o `_updatedBy` (§1.1) do
   projeto deve mudar? Proposta desta mudança: **não** — `updated_by_person_id` reflete
   edição direta da entidade, não propagação. Precisa do aval de `progress-rollup`.
