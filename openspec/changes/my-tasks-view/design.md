# Design — `my-tasks-view`

## Context

§3.6 é uma frase e meia de especificação. A complexidade não está no comportamento
descrito, está em três coisas que a spec legada não precisava dizer porque o Firestore as
resolvia por acidente:

1. **Quem sou "eu"?** No legado, `eu` era uma string: `auth.currentUser.displayName`,
   comparada contra as strings de `task.responsibles`. Frágil (dois "João Silva"
   colidem, renomear o perfil esvazia a lista), mas nunca vazio: o nome sempre existe. No
   alvo, por D10/D11, `eu` é `people.id` — estável, mas **pode não existir**.
2. **Onde eu procuro?** No legado, a coleção do usuário logado era o próprio workspace, e
   o cliente varria a árvore em memória depois de baixá-la inteira. No alvo, é uma
   consulta transversal a todos os projetos do workspace, e o custo é real.
3. **O que "aberta" significa?** §3.6 define por exclusão (`≠ Concluído`, `≠ N/A`), não
   por inclusão. Como §2.2 tem exatamente 4 status, a exclusão é equivalente à inclusão de
   `{Pendente, Em Andamento}` — mas só enquanto o enum tiver 4 valores.

O risco central desta capacidade não é performance nem UX. É **falhar silenciosamente**:
uma lista vazia é um resultado perfeitamente plausível ("não tenho nada atribuído"), então
uma quebra de identidade se disfarça de estado normal e passa por todos os testes de
smoke. Foi exatamente o que o plano anterior produziu.

## Goals / Non-Goals

**Goals**

- Filtrar por `person_id`, com a origem dessa `person_id` explicitada e testada.
- Tornar **impossível** o estado "usuário é membro do workspace mas não tem `Person`" — e,
  onde ainda for possível por dado legado, torná-lo **ruidoso**, nunca uma lista vazia.
- Uma única consulta SQL, sem N+1, com índice nomeado e orçamento de latência medido.
- Escopo de tenant garantido pelo banco (RLS), não pela cláusula `WHERE` do service.
- Ordenação determinística e estável, para que paginação e testes não oscilem.

**Non-Goals**

- Mutação de qualquer espécie a partir desta tela.
- Filtros, ordenação por coluna, busca, agrupamento — fora de §3.6.
- Visão "tarefas de fulano" para gestores.
- Cache materializado (view materializada / tabela de leitura). Ver D-MTV-7.

## Decisions

### D-MTV-1 — O responsável é `person_id`; o nome nunca participa do filtro

A consulta parte de `task_assignees.person_id = :viewer_person_id`. O nome da pessoa não
aparece em nenhum predicado, nem como fallback, nem como desempate.

*Alternativa descartada:* filtro híbrido "`person_id` OU nome bate", para tolerar dado
legado ainda não resolvido pelo importador. Descartado porque reintroduz exatamente a
ambiguidade que D11 aboliu (duas pessoas homônimas passam a ver as tarefas uma da outra —
um vazamento de dado entre usuários do mesmo tenant), e porque criaria um caminho em que a
tela "funciona" com dados que `legacy-data-migration` deveria ter rejeitado, escondendo o
defeito da importação. A resolução nome → `Person` é obrigação do importador
(`legacy-data-migration`, §1.4), não desta tela.

**Onde mora a invariante:** em `task_assignees`, propriedade de `robot-tasks` — chave
primária composta / índice único `(task_id, person_id)` e FK `person_id → people(id)`. Não
existe coluna de texto de responsável em lugar nenhum do esquema. Esta capacidade
**depende** dessa forma e adiciona um teste de esquema que falha se qualquer coluna
`*responsible*`/`*assignee_name*` de tipo texto aparecer em `tasks` ou `task_assignees`.

### D-MTV-2 — A `Person` do viewer é resolvida por `(workspace_id, user_id)`, e a ausência dela é um erro, não um vazio

Resolução: `Person.find_by(workspace_id: current_workspace.id, user_id: current_user.id)`.

Um `User` pode ter **N** `Person`, uma por workspace em que participa (D2/D10). A troca de
workspace no shell troca a `Person` efetiva; a chave de cache
`['ws', wsId, 'my-tasks']` já particiona por workspace, então a troca não reaproveita
resultado (D9 + `app-shell-navigation`, que descarta estado ao trocar de workspace).

Se a `Person` não existir para um usuário que **é** membro do workspace, o endpoint
responde **`409 Conflict`** com código `person_missing` e registra a violação no rastreio
de erro (`delivery-and-observability`). Ele **não** responde `200` com lista vazia.

*Alternativa descartada:* criar a `Person` sob demanda (lazy) aqui, na primeira leitura de
Minhas Tarefas. Descartado por dois motivos. Primeiro, fronteira: `Person` é do domínio de
`workspace-tenancy`, e criar identidade de domínio num endpoint `GET` idempotente é uma
escrita escondida atrás de uma leitura — quebra cache, quebra réplica de leitura, e cria
uma segunda origem de verdade para "como uma Person nasce", divergindo de D10. Segundo, e
pior: **mascara o defeito**. Se o bootstrap do workspace parar de criar a `Person`, o lazy
create faz tudo continuar aparentemente funcionando enquanto notificações (§2.7),
auto-atribuição (§2.3) e atribuição manual (§3.5) seguem quebradas — porque cada um
teria que ter seu próprio lazy create. Falhar alto num lugar é melhor que remendar em
quatro.

*Alternativa também descartada:* `200` com lista vazia e um campo de aviso no payload.
Descartado porque é precisamente a falha silenciosa que motivou esta seção: nenhum teste
de smoke distingue `[]` de `[]`.

**Onde mora a invariante:** `memberships.person_id` é `NOT NULL` com FK
`REFERENCES people(id)` — propriedade de `workspace-tenancy`, citada aqui como
pré-condição. Com essa constraint, "membro sem Person" é **inexpressável no banco**, e o
`409` é defesa em profundidade para linhas escritas antes da constraint (importação
legada). Esta capacidade contribui um **teste de contrato cruzado**: cria um usuário novo,
roda o bootstrap de workspace real de `workspace-tenancy`, e afirma que
`Person.find_by(workspace_id:, user_id:)` existe **antes** de qualquer requisição a
`/my_tasks`. Se `workspace-tenancy` regredir, este teste é o que quebra.

### D-MTV-3 — `person.user_id IS NULL` é um estado legítimo e essa pessoa nunca vê esta tela

D10 torna `people.user_id` anulável de propósito: dá para atribuir uma tarefa a alguém do
chão de fábrica que não tem conta no sistema. Essa pessoa aparece como responsável em
§3.5, recebe atribuição, é contabilizada — e **nunca acessa Minhas Tarefas**, porque não
tem `User`, logo não autentica, logo não emite requisição.

Isso é **correto e declarado**, não um buraco. A consequência prática que precisa estar
escrita: uma tarefa cujo único responsável é uma pessoa sem conta **não aparece na lista de
ninguém**. Ela não "vaza" para o dono nem para um administrador. Quem quer ver essa tarefa
usa a tela do robô (§3.5) ou o relatório (§3.8).

A consulta **não** filtra por `people.user_id IS NOT NULL`: ela já parte da `person_id` do
viewer, que por construção tem `user_id`. Adicionar o predicado seria ruído sem efeito.

### D-MTV-4 — Uma consulta, joins até o projeto, payload achatado

```
SELECT t.id, t.description, t.status, t.progress, t.category,
       r.id AS robot_id, r.name AS robot_name,
       c.id AS cell_id,  c.name AS cell_name,
       p.id AS project_id, p.name AS project_name
FROM task_assignees ta
JOIN tasks    t ON t.id = ta.task_id
JOIN robots   r ON r.id = t.robot_id
JOIN cells    c ON c.id = r.cell_id
JOIN projects p ON p.id = c.project_id
WHERE ta.workspace_id = :ws
  AND ta.person_id    = :viewer_person_id
  AND t.status IN ('pending','in_progress')
ORDER BY p.position, p.id, c.position, c.id, r.position, r.id, t.position, t.id
LIMIT :per_page OFFSET :offset
```

O driver do plano é `task_assignees` (seletividade alta: uma pessoa, dezenas a centenas de
linhas), não `tasks` (dezenas de milhares). Os joins seguem por PK. O `workspace_id`
aparece explicitamente **além** da RLS porque ele também é o prefixo do índice.

*Alternativa descartada:* partir de `tasks` filtrando por status e depois semi-join em
`task_assignees` (`EXISTS`). Descartado porque inverte a seletividade: força varredura do
índice parcial de tarefas abertas do workspace inteiro (~milhares) para depois descartar
99% delas. O plano correto tem a pessoa como ponto de entrada.

*Alternativa descartada:* retornar apenas `task_id` e hidratar o caminho no cliente com
chamadas por robô. Descartado: N+1 clássico, e a tela é de uso móvel em galpão (PRODUCT.md)
— uma requisição por linha é inaceitável em rede ruim.

O payload é **achatado e autossuficiente**: cada linha carrega os nomes de robô/célula/
projeto e os ids necessários para o deep-link. Isso duplica strings na resposta; é aceito
conscientemente em troca de zero requisições adicionais.

### D-MTV-5 — Índices e orçamento de query

Dois índices, ambos criados pela migration desta capacidade (nenhum dos dois é retrofit):

- `idx_task_assignees_ws_person ON task_assignees (workspace_id, person_id) INCLUDE (task_id)`
  — o índice que sustenta o ponto de entrada. `INCLUDE (task_id)` permite index-only scan
  na etapa de driver.
- `idx_tasks_open_ws ON tasks (workspace_id, id) WHERE status IN ('pending','in_progress')`
  — índice **parcial**. Cobre também `robot-task-table` e os hubs; se `hierarchy-screens`
  ou `progress-rollup` já o tiverem criado, esta capacidade o reusa e a migration é no-op
  idempotente (`IF NOT EXISTS`).

**Orçamento:** contra o dataset de carga compartilhado (definido em `progress-rollup`,
exercitado em `quality-and-accessibility`) — 10 projetos × 8 células × 12 robôs × 30
tarefas ≈ **28.800 tarefas**, viewer atribuído a **1.500** delas das quais **~600 abertas**:

- p95 da consulta (primeira página, 50 linhas) **< 120 ms**;
- **zero** seq scan em `tasks` no `EXPLAIN (ANALYZE, BUFFERS)`;
- **exatamente 1** consulta SQL por requisição (assert de contagem de queries no spec — é o
  que pega N+1 introduzido por entity).

Se o dataset de carga ainda não existir quando esta capacidade for implementada, ela o
cria com os mesmos números e `progress-rollup` passa a reusá-lo — mas os números são um
contrato compartilhado e não podem divergir.

*Alternativa descartada:* índice sobre `tasks (workspace_id, status, robot_id)` sem
parcialidade. Descartado porque `done` domina a tabela num workspace maduro (é o estado
terminal de quase tudo) e infla o índice com exatamente as linhas que esta tela nunca lê.

### D-MTV-6 — Ordenação determinística por caminho hierárquico, e paginação por offset

Ordem: projeto → célula → robô → tarefa, cada nível por `position` e desempatado por `id`.
Isso reproduz a ordem manual de drag & drop (§2.9) que o usuário já conhece das telas de
hierarquia, e o desempate por `id` garante estabilidade total — sem ele, duas linhas com a
mesma `position` podem trocar de página entre requisições.

§3.6 pede lista "plana": não há cabeçalho de agrupamento. O caminho aparece nas colunas
Robô/Célula/Projeto de cada linha, repetido. É redundante visualmente e é o que a spec
descreve.

Paginação: `page`/`per_page` (padrão 50, teto 200), com `set_pagination_headers` do
`controller_helpers.rb` já existente no template. Offset é aceitável porque a ordenação é
totalmente determinística e o conjunto do viewer é pequeno (centenas, não milhões).

*Alternativa descartada:* sem paginação, retornar tudo. Descartado: um engenheiro
atribuído a um projeto inteiro em rampa pode ter 600+ tarefas abertas; 600 linhas num
payload achatado com nomes repetidos é uma resposta grande demais para 4G de galpão.

*Alternativa descartada:* cursor keyset. Descartado por desproporção — a chave de cursor
seria a tupla de 8 colunas do `ORDER BY`, e o ganho sobre offset só aparece muito além do
volume real desta lista.

### D-MTV-7 — Sem tabela/view materializada de leitura

A consulta é cara em teoria (transversal a todos os projetos) e barata na prática (a
`person_id` corta cedo). Nada é materializado.

*Alternativa descartada:* view materializada `my_open_tasks` com refresh por trigger ou
job. Descartada por custo de coerência desproporcional: cada avanço (§2.4), cada mudança
de atribuição (§3.5) e cada criação de robô em lote (§2.5) teria que invalidá-la, e uma
lista de tarefas defasada é pior que uma lista lenta — o usuário registra o avanço, volta,
e a tarefa ainda está lá. D5 materializa `progress_cache` porque agregação bottom-up é
genuinamente cara; aqui não é.

### D-MTV-8 — Estado vazio: a spec não o descreve; decidido aqui

§3.6 é omissa. Decisão: **três estados visuais distintos**, nunca colapsados:

1. **Vazio legítimo** (`200`, `[]`): título "Nenhuma tarefa aberta atribuída a você",
   corpo "Tarefas concluídas e marcadas como N/A não aparecem aqui.", e uma ação
   secundária "Ir para Visão Geral". Segue o padrão de estado vazio de `design-system` /
   `hierarchy-screens`; sem ilustração, sem emoji.
2. **Identidade ausente** (`409 person_missing`): mensagem de erro explícita — "Não foi
   possível identificar seu cadastro neste workspace." — com ação "Tentar novamente", e
   `console.error` + rastreio. Nunca se parece com o estado 1.
3. **Falha de rede/servidor** (`5xx`, timeout): estado de erro padrão do shell com
   "Tentar novamente".

A frase "Tarefas concluídas e marcadas como N/A não aparecem aqui" existe porque o modo de
confusão real é o usuário concluir sua última tarefa, a linha sumir, e ele achar que perdeu
dado. Ela é uma string pt-BR centralizada (D14).

### D-MTV-9 — Navegação: deep-link para o robô com a tarefa no query string

Clicar na linha navega para `/ws/:wsId/robots/:robotId?task=:taskId`. Esta capacidade
**fixa o formato** e emite o link; realçar/rolar até a tarefa ao chegar é obrigação de
`robot-task-table`. O parâmetro é query string, não fragmento, para sobreviver ao roteador
e ao service worker.

Compatível com §3.5: o filtro segmentado da tela do robô **reseta para "Todos" a cada
navegação**, então a tarefa vinda de Minhas Tarefas está garantidamente visível ao chegar.
Se o filtro persistisse em "Concluídos", o clique levaria a uma tela onde a tarefa não
aparece — o reset de §3.5 é o que impede isso, e é por isso que é citado aqui.

A linha inteira é o alvo de clique (alvo ≥ 32px, uso com luva), implementada como `<tr>`
com um `<a>` que cobre a primeira célula para preservar teclado, foco e "abrir em nova
aba" — não um `onClick` numa `div` (a11y, `quality-and-accessibility`).

### D-MTV-10 — Autorização

O endpoint declara `MyTasksPolicy` (D3), sujeito ao route-sweep de
`authorization-policies`. A policy exige apenas **membership ativa no workspace**, em
qualquer papel — inclusive `view`, porque §4.1 inv. 4 restringe *mutações* de um membro
`view`, e esta tela não muta nada.

Não há verificação de "posso ver as tarefas de X": o único X possível é o próprio viewer,
derivado do token, **nunca de um parâmetro**. Não existe `?person_id=` neste endpoint.

*Alternativa descartada:* aceitar `person_id` opcional para uso futuro de gestor.
Descartada: cria uma superfície de autorização para um requisito que não existe, e o
caminho negativo ("editor tenta ler tarefas de outro membro") passaria a precisar de teste
e de policy própria por nada.

**Onde mora a invariante de tenant:** RLS em `tasks`, `task_assignees`, `robots`, `cells`,
`projects` sobre `app.current_workspace_id` (D2, `workspace-tenancy`). Mesmo que o service
esquecesse `ta.workspace_id = :ws`, a RLS retornaria zero linhas de outro workspace. O
teste negativo correspondente força os dois caminhos: com o predicado e, num spec que o
remove por stub, só com RLS.

## Risks / Trade-offs

- **Risco principal: `workspace-tenancy` ou `workspace-invitations` regredirem e voltarem
  a não criar `Person`.** Mitigação: o teste de contrato cruzado de D-MTV-2 (bootstrap real
  + aceite real, não factory de `Person` direta) e o `409` ruidoso. Uma factory que cria
  `Person` sozinha esconderia exatamente esta falha — por isso os dois specs de regressão
  são proibidos de usá-la, e o `tasks.md` diz isso.
- **Payload redundante** (nomes de projeto/célula repetidos por linha). Aceito; medido no
  orçamento de resposta. Se incomodar, a saída é normalizar a resposta em `entities` +
  `rows`, não voltar a hidratar no cliente.
- **Offset pagination** degrada em páginas profundas. Irrelevante no volume real; se um
  workspace patológico aparecer, migrar para keyset é local ao service.
- **Índice parcial e o enum de status:** `idx_tasks_open_ws` codifica
  `('pending','in_progress')`. Se `robot-tasks` adicionar um quinto status, o índice e o
  filtro **divergem em silêncio** — o índice continua válido, só deixa de cobrir. Mitigação:
  um spec afirma que o conjunto de status do enum é exatamente
  `{pending, in_progress, done, not_applicable}` e falha se mudar, apontando para este
  arquivo.
- **A exclusão de §3.6 é por status, não por progresso.** Uma tarefa `not_applicable` com
  `progress = 0` some (correto, §2.2 força `N/A → 0`), e uma tarefa `in_progress` com
  `progress = 100` é impossível por §2.2. Não filtramos por progresso; se aparecer uma
  linha inconsistente, o defeito é da máquina de estados de `progress-advances`, e esta
  tela a exibe em vez de escondê-la.

## Plano de migração

Não há dado a migrar. As duas migrations são aditivas e reversíveis:

1. `CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_task_assignees_ws_person …`
2. `CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_tasks_open_ws … WHERE status IN (…)`

`CONCURRENTLY` exige `disable_ddl_transaction!`. `down` é `DROP INDEX IF EXISTS`. Nenhuma
tabela é criada, alterada ou apagada; nenhuma linha é escrita. Não há tarefa destrutiva
nesta capacidade, logo não há backup a fazer.

## Perguntas em aberto

- **Ordenação por urgência.** §3.6 não pede, e a spec não tem prazo/prioridade em `tasks`.
  Fica a ordem hierárquica. Se o produto quiser "mais recente primeiro" depois, o campo
  natural é `recorded_at` do último `task_advance` (D8) — o que exigiria um lateral join e
  uma revisão do orçamento de D-MTV-5. Fora de escopo agora.
- **Contagem no item de menu da sidebar** ("Minhas Tarefas · 12"). Não está em §3.6 nem em
  DESIGN.md. Custaria uma segunda consulta em toda navegação; deixado de fora, decisão de
  `app-shell-navigation` se quiser.
- **Multi-workspace agregado** ("minhas tarefas em todos os meus workspaces"). Conflita
  frontalmente com D2 (RLS por workspace único por request) e não está na spec. Fora.
