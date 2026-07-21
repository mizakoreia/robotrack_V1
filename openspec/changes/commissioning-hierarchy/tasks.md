## 1. Fundação de esquema e identidade (D1, D13)

- [x] 1.1 Migration `enable_pgcrypto` habilitando a extensão e falhando com mensagem
  explícita se o role não tiver permissão de `CREATE EXTENSION`. (§ design D-H1 — sem ela
  `gen_random_uuid()` não existe e a migration de `projects` aborta no meio, deixando a
  base com extensão parcial)
- [x] 1.2 Migration `create_projects`: `id uuid PK DEFAULT gen_random_uuid()`,
  `workspace_id uuid NOT NULL REFERENCES workspaces(id)`, `name`, `position integer NOT NULL`,
  `progress_cache jsonb NOT NULL DEFAULT '{}'`, `progress_cached_at`, `lock_version`,
  `updated_by_person_id uuid REFERENCES people(id) ON DELETE SET NULL`, timestamps;
  `UNIQUE (id, workspace_id)`; `CHECK` de `name`; índices únicos
  `(workspace_id, position) DEFERRABLE INITIALLY DEFERRED` e `(workspace_id, lower(name))`.
  (§1.1, D5 — rodar a migration numa base limpa e conferir que `progress_cache` já existe;
  se faltar, `progress-rollup` terá de retrofitar três migrations já aplicadas)
- [x] 1.3 Migration `create_cells`, mesma estrutura, com
  `FOREIGN KEY (project_id, workspace_id) REFERENCES projects (id, workspace_id) ON DELETE CASCADE`
  e escopo de ordem/nome por `project_id`. (§1.1 — `UPDATE cells SET workspace_id = <outro>`
  no console tem de ser rejeitado pelo banco, não passar silenciosamente)
- [x] 1.4 Migration `create_robots`, com `application text NOT NULL DEFAULT 'Misto / Geral'`
  + `CHECK` dos seis valores literais de §1.2, e FK composta para `cells`. (§1.2 —
  `INSERT ... application = 'Pintura'` falha no Postgres, não só no model)
- [x] 1.5 Migration `enable_rls_on_hierarchy`: `ENABLE` + `FORCE ROW LEVEL SECURITY` e
  política `tenant_isolation` nas três tabelas, usando
  `current_setting('app.current_workspace_id', true)::uuid`. (§4.1 inv. 1, D2 —
  `SELECT count(*) FROM projects` sem a variável setada devolve `0`, não a tabela inteira)
- [x] 1.6 **Verificação:** spec de esquema (`spec/db/hierarchy_schema_spec.rb`) que lê
  `information_schema` e `pg_class` e falha se: alguma `id` não for `uuid`; algum
  `workspace_id` for nullable; `relforcerowsecurity` for `false`; faltar qualquer índice
  único declarado em 1.2–1.4. (§1.1, D13 — este spec é o que impede a próxima capacidade
  de criar uma tabela `bigserial` por hábito do template)

## 2. Models e invariantes de aplicação

- [x] 2.1 Models `Project`, `Cell`, `Robot` com associações, `has_many ... dependent: nil`
  (o cascade é do banco, não do Rails) e `lock_version` ativo. (§1.1 — excluir projeto com
  200 robôs faz **um** `DELETE`, não 200 callbacks; medir a contagem de queries)
- [x] 2.2 Concern `WorkspaceScoped`: preenche `workspace_id` a partir do contexto de
  sessão e levanta erro se alguém tentar atribuí-lo por mass-assignment. (D2 — `POST` com
  `workspace_id` de outro tenant no corpo cria a linha no workspace da sessão, nunca no do corpo)
  *(adaptada — o concern da Onda 1 é REUSADO como está; a proteção contra
  workspace_id injetado é o WITH CHECK da RLS (provado em spec) + os endpoints
  do G3 nem declararem o param — levantar no model mascararia a violação de
  política como erro de validação, o anti-padrão que o próprio concern documenta)*
- [x] 2.3 Concern `PositionScoped`: calcula `position = COALESCE(MAX+1, 0)` do escopo
  dentro da transação do `INSERT`, sob lock do pai. (§2.9 — duas criações simultâneas na
  mesma célula não produzem dois robôs em `position = 3`)
  *(lock = advisory lock transacional sobre o uuid do escopo, não FOR UPDATE:
  o pai de projects é a linha do workspace e o robotrack_app não tem UPDATE de
  tabela nela — armadilha 2 do EXECUCAO, confirmada)*
- [x] 2.4 **Verificação:** specs de model cobrindo nome em branco, nome de 121 chars,
  duplicata case-insensitive no mesmo escopo e nome igual em escopos diferentes.
  (§1.1 — `solda 01` e `Solda 01` no mesmo projeto colidem; no projeto vizinho, não)

## 3. Identidade gerada no cliente e idempotência (D1)

- [x] 3.1 `Hierarchy::IdValidator`: aceita UUID v1–v8 com variante RFC 4122, rejeita UUID
  nulo com mensagem distinta da de formato. (§ design D-H1 —
  `00000000-0000-0000-0000-000000000000` retorna `422` com mensagem própria, não é aceito
  como id válido nem confundido com "id ausente")
- [x] 3.2 `Hierarchy::IdempotentCreate`: `INSERT ... ON CONFLICT (id) DO NOTHING RETURNING *`
  e a tabela de decisão de D-H2 (`201` / `200` replay / `409` divergente / `404` cross-tenant).
  (§4.2 — reenviar o mesmo `POST` de robô 3 vezes produz **uma** linha e responde
  `201, 200, 200`, nunca `201, 409, 409`)
- [x] 3.3 **Verificação:** spec de request provando que `POST` com id existente em outro
  workspace devolve `404` com corpo byte-idêntico ao `404` de id inexistente. (§4.1 inv. 1
  — se as respostas diferirem, a PK vira oráculo de enumeração entre tenants)
  *(no G2 a tabela de decisão é provada em nível de SERVIÇO (:not_found via
  RLS); a metade HTTP byte-idêntica entra na suíte de request do G3, junto com
  os endpoints)*

## 4. Services e endpoints de CRUD

- [x] 4.1 `ProjectsService` (create/update/destroy) no contrato `ApiResponseHandler`,
  gravando `updated_by_person_id`/`updated_at` e a entrada de auditoria na **mesma**
  transação do `DELETE`. (§2.8 — auditoria que falha reverte a exclusão; a célula continua
  existindo e a API responde `500`, não `204`)
- [x] 4.2 `CellsService`, mesmo contrato, validando que o `project_id` alvo é visível sob
  RLS antes de criar. (§3.3 — criar célula sob projeto de outro workspace responde `404`,
  não `403`)
- [x] 4.3 `RobotsService`, mesmo contrato, com `application` default e validação de enum.
  (§3.4 — robô criado sem `application` sai como `Misto / Geral`, não `NULL`)
- [x] 4.4 Entities `Api::Entities::{Project,Cell,Robot}` que sempre emitem coleções como
  array e traduzem `progress_cache = '{}'` em `{weighted: 0, done: 0, total: 0}`.
  (§1.4 — projeto sem células serializa `"cells": []`; se sair `null`, a grade de
  `hierarchy-screens` quebra no `.map`)
- [x] 4.5 Endpoints Grape em `app/controllers/api/v1/{projects,cells,robots}.rb` + as três
  linhas de `mount` em `api/v1/base.rb`, cada rota declarando sua policy. (D3 — o
  route-sweep de `authorization-policies` falha se uma rota subir sem declaração)
- [x] 4.6 Policies `ProjectPolicy`, `CellPolicy`, `RobotPolicy` em `app/policies/`,
  idioma singleton, mapeando §4.1: leitura para os três papéis, escrita só `owner`/`edit`.
  (§4.1 — membro `view` recebe `403` no `POST` e `200` no `GET`, na mesma sessão)
- [x] 4.7 **Verificação:** suíte de request cobrindo os cenários negativos — `view`
  criando, `view` excluindo, `view` reordenando, usuário de `W2` lendo e escrevendo em
  `W1`, e renomeação concorrente `409`. (§4.1 — cada um desses cinco tem de falhar pelo
  motivo certo: `403` para papel, `404` para tenant, `409` para `lock_version`)

## 5. Ordenação manual (§2.9)

- [x] 5.1 `Hierarchy::ReorderService` genérica por escopo: `FOR UPDATE` no pai, comparação
  de conjunto de ids, renumeração `0..n-1` numa transação. (§2.9 — falha na 5ª de 8 linhas
  deixa as 8 nas posições originais, sem duplicata nem buraco)
- [x] 5.2 Endpoints `PATCH /api/v1/{projects,cells,robots}/reorder` recebendo
  `{scope_id, ordered_ids}`, com policy declarada; `position` removida dos params de
  `PATCH` de item. (§2.9 — `PATCH /cells/<id>` com `{"position": 0}` não move a célula)
- [x] 5.3 Detecção de conflito: conjunto divergente → `409` com o conjunto atual, sem
  escrita. (§2.9 — irmão criado por outra pessoa entre o carregamento e o drop produz
  `409`, não uma lista onde o item novo some ou fica órfão em `position = 3` duplicada)
- [x] 5.4 **Verificação:** spec de concorrência com duas threads reordenando o mesmo
  projeto e spec provando que reordenar não incrementa `lock_version`. (§2.9 — sem
  deadlock, sem posição duplicada, e um `PATCH` de renome com `lock_version` antigo
  continua válido depois de uma reordenação)

## 6. Cliente — API, hooks e drag & drop

- [x] 6.1 `lib/api/endpoints.ts`: grupo `hierarchy` com os 10 verbos (3× create, 3× update,
  3× destroy, reorder por escopo) tipados. (D9 — nenhuma chamada nova usa
  `useEffect + apiClient`, o padrão de dívida do template)
- [x] 6.2 `lib/ids.ts` com `newId()` sobre `crypto.randomUUID()` e fallback para ambiente
  sem `crypto.randomUUID` (Safari antigo, contexto não-seguro). (D1 — o fallback tem de
  gerar UUID v4 válido; se gerar string qualquer, todo `POST` offline volta `422` ao
  sincronizar)
- [x] 6.3 Hooks React Query `useProjects`, `useCells`, `useRobots` com as chaves de D9
  (`['ws', wsId, 'projects']`, `['ws', wsId, 'project', pid, 'cells']`,
  `['ws', wsId, 'cell', cid, 'robots']`). (D9 — as chaves são as que
  `realtime-collaboration` vai invalidar; divergir delas quebra o tempo real sem erro visível)
- [x] 6.4 Mutations de create/rename/destroy com atualização otimista usando o `id` gerado
  em 6.2 e rollback no `onError`. (§4.2 — criar robô com a rede caída mostra o card na
  hora e o card **não** duplica quando a sincronização confirma)
  *(o "não duplica" tem teste; o ROLLBACK do create não — no vitest 1.x + jsdom
  a rejeição de mutation do React Query vira unhandled rejection e reprova o
  arquivo, com `onError` no hook, no `mutate` E no MutationCache. O mesmo padrão
  snapshot→restore está coberto pelo caminho de conflito de `useReorder`.
  Revisitar quando `quality-and-accessibility` subir o vitest)*
- [x] 6.5 Handler de drag & drop com alça dedicada que monta `ordered_ids` completo e trata
  `409` recarregando o escopo. (§2.9 — arrastar depois que outra pessoa criou um irmão
  mostra aviso e recarrega, em vez de gravar uma ordem que apaga o item novo da lista)
  *(a ALÇA visual é de `hierarchy-screens`; aqui entram a função pura `moveItem`,
  o `submitReorder` que classifica o 409 e o hook `useReorder` que restaura a
  lista — tudo plugável na tela futura, EXECUCAO decisão 5)*
- [x] 6.6 **Verificação:** teste Vitest do fluxo de reordenação com `409` mockado e do
  fallback de `newId()`. (§2.9 — após o `409` a lista volta ao estado do servidor, não fica
  presa na ordem otimista que o servidor rejeitou)

## 7. Fechamento

- [x] 7.1 Seed de desenvolvimento com 2 workspaces, 3 projetos, 6 células e 12 robôs, em
  que os dois workspaces têm projetos de **mesmo nome** e ids adjacentes. (§4.1 — dataset
  onde um vazamento de tenant é visível a olho nu no teste, em vez de passar despercebido)
- [x] 7.2 **Verificação:** spec de contrato de esquema exigindo que as FKs de `tasks` para
  `robots` (declaradas por `robot-tasks`) sejam `ON DELETE CASCADE`, falhando se vierem
  `RESTRICT` ou `SET NULL`. (§ design D-H6 — este spec é a aresta explícita entre esta
  capacidade e `robot-tasks`; sem ele, excluir projeto com tarefas passa a devolver `500`
  de violação de FK em produção)
