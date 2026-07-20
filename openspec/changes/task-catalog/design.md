# Design — `task-catalog`

## Context

O legado guardava o catálogo como `workspace.defaultTasks`: um array de objetos dentro do
documento do workspace no Firestore. Consequências que herdamos como problema a resolver:

- **Sem tipo.** `appFilters` era um array de strings livres. Nada impedia
  `["solda ponto"]` (minúsculo) ou `["Sealing", "Sealing"]`.
- **Dois nomes para o mesmo campo.** `apps` foi renomeado para `appFilters` e a leitura
  passou a aceitar os dois (§1.4 item 3). Documentos antigos nunca foram reescritos.
- **Duas sentinelas para o mesmo significado.** §2.5 diz que o template se aplica se o
  filtro contém `"Misto / Geral"` **ou** `"Todas"`. `"Misto / Geral"` é um valor legítimo
  do enum §1.2 (um robô pode *ser* misto); `"Todas"` **não é** — é sentinela pura, nunca
  aparece em §1.2.
- **Ordenação implícita.** A ordem das 9 categorias na tela vem da ordenação lexicográfica
  da string `cat`, que começa com `A.`, `B.`, … Não existe campo de ordem.

O alvo é Postgres + Grape + React Query. O catálogo é lido em dois caminhos quentes
(criação de robôs em lote e sincronização retroativa) e escrito raramente, por humano, na
tela de configurações.

## Goals / Non-Goals

**Goals**

1. O enum de Aplicações (§1.2) tem **um** ponto de verdade, no banco, e o frontend o
   consome em vez de redeclarar.
2. A regra de filtro (§2.5) existe em **um** lugar de código, usado por §2.5 (lote) e §2.6
   (sync). Divergência entre os dois caminhos é o modo de falha clássico deste subsistema.
3. Seed fiel: 31 itens, 9 categorias, `weight: 1`, exatamente três desvios de "todas".
4. Sync retroativa aditiva, nunca destrutiva, com contagem honesta.
5. Isolamento de tenant garantido por RLS (D2), não por `where` no service.

**Non-Goals**

- Propagar edição de template para tarefas já materializadas.
- UI (é de `workspace-settings`).
- Qualquer semântica de `weight` além de "número copiado com default 1".

## Decisions

### D-TC-1 — O prefixo de ordenação fica **dentro** da string `cat`

`cat` é `text` e guarda `"A. Hardware"`, `"B. Rede"`, … A ordenação de categorias na
leitura é `ORDER BY cat, desc`, exatamente a ordenação lexicográfica descrita em §1.3.

**Alternativa descartada:** coluna `category_position smallint` (ou tabela
`task_categories` normalizada) com `cat` guardando só `"Hardware"`. É objetivamente mais
limpo — ordenação explícita, categoria renomeável sem quebrar ordem — e foi descartada por
três razões concretas:

1. **`tasks.cat` é uma string copiada.** `robot-tasks` copia `cat` do template para a
   tarefa (§1.1: a Tarefa tem `cat` como texto, agrupador visual). Se o template tivesse
   `position` e a tarefa não, a tabela do robô (`robot-task-table`, §3.5, agrupamento por
   categoria) perderia a ordem ou precisaria de um join de volta ao catálogo — join que
   não pode existir, porque a tarefa é snapshot e o template pode ter sido apagado.
   Propagar `position` para `tasks` significa desnormalizar a ordem em cada tarefa: o
   mesmo problema, com mais colunas.
2. **O relatório (§3.8) e o export de backup (§3.11) são textuais.** O usuário já lê e
   reconhece `"A. Hardware"`. O prefixo é conteúdo do produto, não artefato acidental.
3. **A migração legada** (`legacy-data-migration`) recebe `cat` já com prefixo. Separar
   exigiria parsing por regex de dado sujo do cliente, com fallback indefinido para
   categorias criadas à mão sem prefixo.

**Isto é frágil e a fragilidade é assumida.** O modo de falha é: usuário cria a categoria
`"Otimização"` sem prefixo e ela ordena depois de `"I. Aceitação"`. Mitigação, não cura:

- A criação de template **não valida** o formato do prefixo (não vamos rejeitar uma
  categoria que o usuário quer). Categoria sem prefixo é válida e ordena ao fim do bloco
  de letras maiúsculas — comportamento determinístico, documentado.
- A **ordenação é feita no banco com collation explícita** (`ORDER BY cat COLLATE "C"`),
  não pela collation do locale. Sem isso, `pt_BR.UTF-8` ignora pontuação em alguns pontos
  e a ordem deixa de ser previsível entre ambientes — um bug que só aparece em produção.
  Um teste compara a ordem retornada com a sequência literal `A.`…`I.`.
- `workspace-settings` sugere o próximo prefixo livre ao criar categoria nova. É
  conveniência de UI, citada aqui como dependência, não garantia.

### D-TC-2 — As duas sentinelas se resolvem por **normalização na escrita**, tolerância na leitura

`app_filters` é `text[] NOT NULL DEFAULT '{}'`. Regra:

- **Na escrita** (create/update, §3.9), o service normaliza antes de persistir: se o array
  recebido está vazio, ou contém `"Misto / Geral"`, ou contém `"Todas"`, grava `{}`.
  Duplicatas são removidas; a ordem é preservada. Isso implementa literalmente a regra de
  §3.9 ("escolher `Misto / Geral` limpa o filtro") e faz `"Todas"` — que nem é valor do
  enum §1.2 — **nunca chegar ao banco em dado novo**.
- **Na leitura/filtro** (§2.5), a checagem continua aceitando as três formas, porque dado
  importado pelo `legacy-data-migration` pode ter `"Todas"` gravado. A predicate é a de
  §2.5, integral, sem simplificação "já normalizamos".

**Alternativa descartada:** normalizar tudo num backfill e simplificar o filtro para
`app_filters = '{}' OR robot.application = ANY(app_filters)`. Descartada porque a
importação legada roda *depois* desta capacidade (Onda 9) e escreve direto na tabela; um
filtro simplificado transformaria um `"Todas"` importado em "aplica-se a nenhum robô" —
falha silenciosa, catálogo que some. A predicate completa custa duas comparações.

**Onde a invariante mora:**
- Domínio dos valores: `CHECK (app_filters <@ ARRAY[...os 6 valores do enum...])` na
  tabela — um array de `text` com CHECK, e não `robot_application[]`, porque um valor
  legado `"Todas"` precisa ser *armazenável* pela importação sem quebrar o INSERT. O CHECK
  admite os 6 do enum **mais** `"Todas"`, e só eles. Lixo tipo `"solda ponto"` é rejeitado
  pelo banco, não pelo model.
- `"Misto / Geral"` nunca persistido em dado novo: garantido pelo service de normalização
  **e** por um teste que insere via console (`TaskTemplate.create!`) e verifica que o
  callback de normalização no model também dispara — model + service, porque este é o
  único caso onde a normalização não é expressável como constraint sem virar trigger
  (uma trigger `BEFORE INSERT OR UPDATE` foi considerada; descartada por opacidade em
  debug de seed, e porque o CHECK já barra o lixo, que é o risco real).

### D-TC-3 — O enum de Aplicação é tipo Postgres, servido ao frontend

`CREATE TYPE robot_application AS ENUM ('Misto / Geral', 'Solda Ponto', 'Solda MIG',
'Handling', 'Sealing', 'Outros')`, usado por `robots.application`
(`commissioning-hierarchy` é dono da coluna; esta capacidade é dona do **tipo**, e a
migration do tipo precede a daquela — aresta explícita em `tasks.md`).

Os rótulos são pt-BR e são **valores**, não chaves de i18n. Isso viola parcialmente D14
(strings pt-BR centralizadas) e a violação é consciente: os rótulos vêm de dados legados
gravados como texto, aparecem em export de backup (§3.11) e em filtros de template. Trocar
por chaves (`spot_welding`) exigiria uma tabela de tradução no importador e no exportador,
para um produto monolíngue. Registrado como dívida em Perguntas em aberto.

**Alternativa descartada:** `varchar` + validação `inclusion` no Rails. Rejeitada por D2 e
pela barra do briefing (item 5): um `UPDATE robots SET application='xpto'` por console
passaria, e a criação em lote de robôs (`robot-tasks`) passaria a filtrar templates contra
um valor inexistente, gerando robôs sem tarefa nenhuma — falha que só aparece semanas
depois, no relatório.

**Endpoint** `GET /api/v1/meta/robot_applications` devolve a lista na ordem do enum. O
frontend consome via React Query (`['meta','robot_applications']`, D9), com `staleTime`
infinito. Sem segunda lista em TS.

### D-TC-4 — O seed é um hook de bootstrap de workspace, com dados num arquivo único

`Workspaces::SeedDefaultTaskTemplatesService` lê uma constante de
`backend/app/services/task_templates/default_catalog.rb` (array de 31 hashes, literal, em
ordem de categoria) e faz **um** `insert_all` no workspace recém-criado. Chamado pelo
bootstrap de `workspace-tenancy` (D10), dentro da **mesma transação** do
`Workspace.create` — um workspace sem catálogo é um workspace quebrado, e commit parcial
seria pior que falha.

**Alternativa descartada:** `db/seeds.rb` com uma tabela global de templates "de sistema"
herdada por referência. Descartada porque §3.9 permite **editar e excluir** qualquer item
do catálogo; herança por referência exigiria copy-on-write por linha, e o legado não tem
esse conceito — `defaultTasks` sempre foi propriedade do workspace.

O arquivo de catálogo tem um teste que trava os números: **31 itens, 9 categorias
distintas, `weight == 1` em todos, exatamente 3 com `app_filters` não vazio**, e compara
o conjunto de `desc` com uma lista literal transcrita de §1.3. Se alguém adicionar um
item, o teste falha e força a decisão de atualizar a spec.

### D-TC-5 — Compatibilidade `apps` só na fronteira da API

O parâmetro `apps` (§1.4 item 3) é aceito **exclusivamente** no coerce de params do Grape
(`Api::V1::TaskTemplates`), que o converte para `app_filters` antes de chamar o service.
Se ambos vierem, `appFilters` vence e um warning estruturado é logado. A resposta da
entity é sempre `appFilters`. Nenhuma camada abaixo do endpoint conhece o nome `apps`.

**Alternativa descartada:** `alias_attribute :apps, :app_filters` no model. Rejeitada
porque espalharia o nome legado por todo o backend, inclusive na entity, perpetuando a
ambiguidade que a §1.4 existe para *tolerar*, não para adotar.

### D-TC-6 — Sync retroativa: dedup por `desc` normalizada, escopo de robô, transação única

`TaskTemplates::SyncToRobotService.call(robot:, actor:)`:

1. Policy check (`TaskTemplatePolicy.sync?` → `owner`/`edit`).
2. `SELECT` dos templates do workspace que passam a predicate §2.5 contra
   `robot.application`.
3. `SELECT desc FROM tasks WHERE robot_id = $1` — conjunto de descrições existentes.
4. Diferença; `insert_all` das restantes com `progress: 0`, `status: 'Pendente'`, sem
   responsável, `position` continuando a maior `position` atual do robô.
5. Retorna `{ added_count: N }`.

Passos 3–4 numa transação com `SELECT ... FOR UPDATE` na linha do robô, para que duas
sincronizações concorrentes (dois engenheiros, mesmo robô) não insiram a mesma `desc`
duas vezes. **Além disso**, a garantia real é um índice único parcial
`CREATE UNIQUE INDEX ON tasks (robot_id, lower(btrim(desc)))` — que pertence a
`robot-tasks` (dona da tabela `tasks`) e é **requisito explícito** desta capacidade sobre
aquela, registrado em `tasks.md` como aresta. Sem o índice, o lock é só otimização e a
dedup vira convenção.

Comparação de `desc` é **case-insensitive e trim-insensitive** (`lower(btrim(...))`).
§2.6 diz apenas "cuja `desc` já exista"; a leitura literal (igualdade exata) faria
`"tcp check "` com espaço à direita — dado plausível vindo do legado — duplicar
`"TCP Check"`. A escolha é declarada aqui porque é uma interpretação, não uma leitura.

**Alternativa descartada:** dedup por `template_id` guardado em `tasks`. Seria mais
robusto (renomear o template não quebra a dedup), mas §2.6 é explícita em usar `desc`, e
tarefas criadas à mão no robô (`robot-tasks`, §3.5) não têm template de origem — ficariam
invisíveis à dedup e seriam duplicadas pela primeira sync.

### D-TC-7 — Isolamento e autorização

- **Tenant:** RLS em `task_templates` com `app.current_workspace_id` (D2). Um template de
  outro workspace não é "404 no service" — é linha invisível ao `SELECT`. O teste
  negativo faz `GET /api/v1/task_templates/<id de outro ws>` com sessão válida e espera
  `404`, e verifica no log que zero linhas foram retornadas pelo banco.
- **Papel:** `TaskTemplatePolicy` (D3), declarada em todo endpoint; o route-sweep de
  `authorization-policies` falha o CI se faltar. `view` lê; `owner`/`edit` escrevem e
  sincronizam (§4.1). Membro `view` tentando `POST /task_templates` recebe `403` e
  **nenhuma linha é escrita** — o teste conta as linhas antes e depois.

## Risks / Trade-offs

| Risco | Impacto | Mitigação |
|---|---|---|
| Prefixo de categoria digitado errado (`"J Aceitação"` sem ponto) desordena a tela | Cosmético, mas confunde no relatório | `ORDER BY cat COLLATE "C"` torna a ordem determinística; sugestão de prefixo em `workspace-settings`; sem validação bloqueante (D-TC-1) |
| Divergência entre o filtro de §2.5 usado no lote e o usado na sync | Robô criado com um conjunto de tarefas e sincronizado com outro | Um único `TaskTemplates::ApplicabilityFilter`; teste compartilhado roda a mesma tabela de casos pelos dois caminhos |
| Seed dentro da transação de bootstrap alonga o 1º login | 31 inserts, ~ms | `insert_all` único; medido no teste de bootstrap |
| Editar um template não afeta tarefas já criadas — usuário pode esperar que afete | Confusão de produto | Comportamento intencional (snapshot); `workspace-settings` exibe aviso; §2.6 é a saída explícita |
| `"Todas"` importado pelo legado + filtro simplificado por alguém no futuro | Catálogo silenciosamente vazio para todos os robôs | Teste que insere `app_filters = '{Todas}'` direto no banco e exige que o template apareça para um robô `Solda MIG` |
| Enum como rótulo pt-BR conflita com D14 | Dívida de i18n se houver 2º idioma | Registrado em Perguntas em aberto; endpoint de metadados é o único ponto a mudar |

## Plano de migração

Não há dado em produção. A ordem das migrations é a que importa:

1. `CREATE TYPE robot_application` — **precisa preceder** a migration de
   `commissioning-hierarchy` que cria `robots.application`. Como aquela capacidade está na
   Onda 3 e esta na Onda 4, a migration do tipo é entregue aqui com timestamp anterior
   **e** `commissioning-hierarchy` referencia o tipo. Se a hierarquia já tiver criado a
   coluna como `varchar`, esta capacidade entrega um `ALTER TABLE robots ALTER COLUMN
   application TYPE robot_application USING application::robot_application`, precedido de
   tarefa de backup (ver `tasks.md`) — é conversão de tipo em coluna existente, portanto
   destrutiva se houver valor fora do enum.
2. `CREATE TABLE task_templates` + CHECK + índices + policy RLS.
3. Backfill: nenhum. Workspaces existentes: nenhum.
4. Rollback: `DROP TABLE task_templates` é seguro (nada referencia; `tasks` guarda cópias,
   não FK). `DROP TYPE robot_application` **não** é seguro após o passo 1 — o rollback
   reverte a coluna para `varchar` antes.

## Perguntas em aberto

1. **`"Todas"` deve ser aceito na API de escrita, ou só tolerado na leitura?** A decisão
   atual: aceito na escrita e normalizado para `{}` (não há razão para rejeitar), mas o
   CHECK o permite armazenado para o importador. Se `legacy-data-migration` decidir
   normalizar na importação, o CHECK pode ser apertado para os 6 valores do enum — decisão
   de lá, não daqui.
2. **Categoria como entidade de primeira classe** (renomear "D. Processo" em todos os
   templates e tarefas de uma vez) é pedido plausível de produto. Não está no escopo de
   §3.9 e ficou de fora. Se entrar, D-TC-1 precisa ser revisitada.
3. **Rótulos do enum em pt-BR vs. D14.** Mantido como valor. Revisitar apenas se houver
   requisito de 2º idioma.
