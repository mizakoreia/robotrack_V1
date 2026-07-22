# Tarefas — `my-tasks-view`

Pré-condição de onda: `progress-advances` e `app-shell-navigation` entregues; `Person`
sendo criada por `workspace-tenancy` (bootstrap do dono) e `workspace-invitations`
(aceite). O grupo 1 existe para **provar** essa pré-condição antes de qualquer código.

## 1. Provar a pré-condição de identidade (D10)

- [x] 1.1 Escrever spec de contrato cruzado que executa o **bootstrap real** de workspace
  de `workspace-tenancy` para um `User` novo e afirma que
  `Person.find_by(workspace_id:, user_id:)` existe e tem `user_id` preenchido.
  Proibido criar `Person` por factory neste spec.
  (§3.6 / D10 — se o bootstrap parar de criar a `Person`, este spec falha antes de
  Minhas Tarefas retornar vazio para o dono e ninguém perceber)
- [x] 1.2 Escrever spec de contrato cruzado equivalente para o **aceite real de convite**
  de `workspace-invitations`, cobrindo os dois ramos: e-mail casa com `Person` existente
  (reusa) e e-mail não casa (cria nova).
  (§3.10 / D10 — o ramo "casa por e-mail" que reusa a `Person` errada faria o convidado
  ver as tarefas de outra pessoa; o ramo "não casa" que não cria nada o deixaria com lista
  vazia permanente)
- [x] 1.3 Escrever spec de esquema afirmando `memberships.person_id NOT NULL` + FK para
  `people(id)`, e que nenhuma coluna de texto `*responsible*`/`*assignee_name*` existe em
  `tasks` ou `task_assignees`.
  (D11 — uma coluna de texto sobrevivente reabre o filtro por nome e faz homônimos verem
  as tarefas um do outro)
- [x] 1.4 **Verificação:** rodar 1.1–1.3 e confirmar que os três **falham** com o
  bootstrap de `Person` desabilitado por stub, e passam com ele ativo.
  (prova de que o spec detecta a regressão, e não apenas passa por acaso)

## 2. Consulta e índices

- [x] 2.1 Migration aditiva com `disable_ddl_transaction!` criando
  `idx_task_assignees_ws_person ON task_assignees (workspace_id, person_id) INCLUDE (task_id)`
  via `CREATE INDEX CONCURRENTLY IF NOT EXISTS`; `down` faz `DROP INDEX IF EXISTS`.
  (design D-MTV-5 — sem `INCLUDE (task_id)` o driver deixa de ser index-only e o p95 estoura)
- [x] 2.2 Migration aditiva criando o índice **parcial**
  `idx_tasks_open_ws ON tasks (workspace_id, id) WHERE status IN ('pending','in_progress')`,
  idempotente caso `hierarchy-screens`/`progress-rollup` já o tenham criado.
  (D-MTV-5 — índice não-parcial infla com `done`, que domina um workspace maduro e nunca é
  lido por esta tela)
- [x] 2.3 Escrever spec que afirma que o enum `tasks.status` tem exatamente
  `{pending, in_progress, done, not_applicable}`, com mensagem de falha apontando para
  `design.md` D-MTV-5.
  (§2.2 — um quinto status faria o índice parcial deixar de cobrir a consulta **em
  silêncio**, sem quebrar nada)
- [x] 2.4 Implementar `MyTasks::ListService` (singleton, `ApiResponseHandler`) com a
  consulta única de D-MTV-4: driver em `task_assignees`, joins até `projects`, filtro de
  status e de `workspace_id`.
  (§3.6 — partir de `tasks` em vez de `task_assignees` inverte a seletividade e varre as
  28.800 tarefas do workspace para descartar 99%)
- [x] 2.5 Implementar a ordenação total de D-MTV-6 (`position` + desempate por `id` nos 4
  níveis) e paginação `page`/`per_page` (padrão 50, teto 200).
  (§3.6 — sem o desempate por `id`, duas células com a mesma `position` fazem uma linha
  aparecer na página 1 e na página 2 da mesma consulta)
- [x] 2.6 **Verificação:** spec de integração com 120 tarefas abertas afirmando que a união
  das páginas 1–3 tem 120 `task_id` distintos, e que 5 requisições da página 1 retornam a
  mesma ordem.
  (§3.6 — pega duplicação/omissão por ordenação instável)

## 3. Endpoint, autorização e resolução do viewer

- [x] 3.1 Implementar a resolução do viewer por
  `Person.find_by(workspace_id:, user_id:)` no service, retornando `409 person_missing` +
  registro no rastreio de erro quando ausente; nenhuma criação de `Person`.
  (D-MTV-2 — responder `200 []` aqui é a falha silenciosa que motivou esta capacidade:
  indistinguível de "não tenho tarefas")
- [x] 3.2 Criar `Api::Entities::MyTaskRow` com o payload achatado (descrição, status,
  progresso, nomes e ids de robô/célula/projeto).
  (D-MTV-4 — entity que resolve associação por método dispara N+1 e destrói o orçamento)
- [x] 3.3 Criar o endpoint `GET /api/v1/workspaces/:workspace_id/my_tasks`, montá-lo em
  `api/v1/base.rb`, declarar `MyTasksPolicy` (D3) exigindo membership em qualquer papel, e
  aplicar `set_pagination_headers`.
  (§4.1 inv. 1 — endpoint sem policy declarada é reprovado pelo route-sweep de
  `authorization-policies`)
- [x] 3.4 Garantir que o endpoint **não** aceita `person_id` como parâmetro: qualquer
  parâmetro nesse sentido é ignorado, e o viewer vem só do token.
  (D-MTV-10 — `?person_id=` aceito transformaria uma tela pessoal em leitura das tarefas
  de qualquer colega)
- [x] 3.5 **Verificação:** specs de request cobrindo `401` sem token (inclusive com
  `X-Skip-Auth: 1`), `403` para não-membro, `200` para papel `view`, e `?person_id=P2`
  retornando apenas tarefas de `P1`.
  (§4.1 inv. 1 e 4 — `X-Skip-Auth` é a brecha do template; se `seal-template-baseline`
  regredir, este spec pega)

## 4. Provas de comportamento de §3.6

- [x] 4.1 Spec: tarefa `in_progress` com `progress: 45` atribuída ao viewer aparece com os
  6 campos das colunas corretos.
  (§3.6 — caminho feliz; falha se algum nome de coluna do payload divergir do contrato)
- [x] 4.2 Spec: a mesma tarefa recebe avanço `45 → 100` pelo fluxo real de
  `progress-advances`, vai a `done` por §2.2, e some da lista na consulta seguinte.
  (§2.2 + §3.6 — filtro aplicado no cliente em vez do servidor passaria neste teste só por
  sorte; combinar com 5.2, que conta as queries)
- [x] 4.3 Spec: tarefa `not_applicable` atribuída ao viewer não aparece; tarefa `pending`
  com `progress: 0` aparece.
  (§3.6 — filtrar por `progress > 0` em vez de por status esconderia a tarefa pendente
  legítima e exibiria a `N/A`)
- [x] 4.4 Spec: tarefa atribuída só a `P2` não aparece para `P1`; tarefa com
  `[P1, P2, P3]` aparece exatamente uma vez para `P1`.
  (§3.6 — join com `task_assignees` sem `DISTINCT`/sem partir da linha do viewer duplica a
  tarefa uma vez por responsável)
- [x] 4.5 Spec: `Person(user_id: NULL)` como único responsável de uma tarefa aberta — a
  tarefa não aparece na lista de ninguém, inclusive do dono, e continua aparecendo nos
  chips da tela do robô.
  (D10 / D-MTV-3 — "consertar" isso mostrando a tarefa ao dono transformaria a tela pessoal
  numa fila de gestão que a spec não pede)
- [x] 4.6 **Verificação (regressão da `Person` faltante):** spec end-to-end que cria um
  usuário novo, roda o bootstrap real, cria projeto → célula → robô → tarefa **sem
  responsável**, registra um avanço `0 → 20` (auto-atribuição §2.3) e afirma
  `200` com exatamente 1 linha. Proibido usar factory de `Person`.
  (§2.3 + §3.6 + D10 — este é o teste que o plano anterior não tinha: sem ele, a lista
  volta vazia para o dono do workspace e nada acusa)

## 5. Isolamento de tenant

- [x] 5.1 Spec negativo: `U1` com `Person` em `W1` e `W9`; tarefa aberta de `W9` não
  aparece em `GET /workspaces/W1/my_tasks`, e as contagens por workspace são 3 e 1.
  (D2 — filtro por `user_id` sem escopo de workspace misturaria as duas listas)
- [x] 5.2 Spec de RLS: com o predicado `task_assignees.workspace_id = :ws` removido por
  stub, nenhuma linha de `W9` retorna.
  (D2 — prova que o isolamento está no banco e não numa cláusula `WHERE` esquecível)
- [x] 5.3 **Verificação:** spec de contagem de queries afirmando exatamente 1 consulta SQL
  de domínio por requisição com 50 linhas.
  (D-MTV-4 — pega N+1 introduzido por entity ou por serializer)

## 6. Tela

- [x] 6.1 Criar `MinhasTarefasPage` com React Query sob `['ws', wsId, 'my-tasks']` (D9) e
  registrar a rota na sidebar do shell.
  (D9 — `useEffect + apiClient` é dívida do template e não se propaga; sem a chave
  correta, `realtime-collaboration` não consegue invalidar)
- [x] 6.2 Renderizar a tabela com as 6 colunas de §3.6: `%` com `tabular-nums`, status como
  **badge** do `design-system`, sem nenhum controle de mutação.
  (§3.6 + regra dura do DESIGN — badge que se parece com seletor faz o usuário tentar
  mudar status daqui e a tela não responder)
- [x] 6.3 Implementar a linha clicável como `<a href="/ws/:wsId/robots/:robotId?task=:taskId">`
  cobrindo a linha, alvo ≥ 32px, funcional por `Tab` + `Enter` e por "abrir em nova aba".
  (D-MTV-9 — `onClick` numa `div` quebra teclado, foco e ctrl+clique; PRODUCT.md descreve
  uso com luva)
- [x] 6.4 Implementar os três estados de D-MTV-8 (vazio legítimo, `409 person_missing`,
  erro de rede) como componentes distintos, com todas as strings vindas do módulo único
  (D14).
  (D-MTV-8 — colapsar `409` em estado vazio reintroduz a falha silenciosa no cliente,
  mesmo com o servidor correto)
- [x] 6.5 Implementar o refluxo mobile da tabela (empilhamento em cartão, caminho
  projeto/célula/robô como linha secundária) sem rolagem horizontal.
  (PRODUCT.md — a tela é usada em celular no chão de fábrica; 6 colunas em 375px sem
  refluxo forçam zoom)
- [x] 6.6 Assinar a invalidação de `['ws', wsId, 'my-tasks']` em eventos de tarefa e de
  atribuição do `WorkspaceChannel` (D6), e garantir descarte do cache ao trocar de
  workspace.
  (D6 — sem isso o usuário conclui a tarefa no robô, volta, e ela ainda está listada)
- [x] 6.7 **Verificação:** testes de componente (Vitest + Testing Library) cobrindo os três
  estados, a navegação por `Enter`, a ausência de controles de mutação, e a troca de
  workspace não exibindo linhas do workspace anterior em nenhum quadro.
  (D-MTV-8 + D-MTV-2 — o teste do `409` é o que impede o cliente de reintroduzir a lista
  vazia enganosa)

## 7. Desempenho

- [x] 7.1 Criar (ou reusar de `progress-rollup`) a factory do dataset de carga com os
  números de D-MTV-5: 10 × 8 × 12 × 30 ≈ 28.800 tarefas, viewer com 1.500 atribuições e
  ~600 abertas.
  (D-MTV-5 — números divergentes entre capacidades tornam os orçamentos incomparáveis e
  inúteis)
- [x] 7.2 **Verificação:** spec de desempenho afirmando p95 < 120 ms na primeira página e
  ausência de `Seq Scan on tasks` no `EXPLAIN (ANALYZE, BUFFERS)`, com o resultado do
  `EXPLAIN` anexado à saída em caso de falha.
  (D-MTV-5 — sem o assert de plano, a perda do índice só aparece em produção, quando a
  tabela cresce)
