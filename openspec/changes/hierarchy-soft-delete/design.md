# Design — hierarchy-soft-delete

## Contexto

`tasks` já resolve o conflito soft-delete×imutabilidade (`deleted_at` + `default_scope`).
Esta change generaliza o padrão para `projects`/`cells`/`robots` e — a parte difícil —
garante que **nenhum leitor conte um nó arquivado**, incluindo os que leem por SQL cru
(views de progresso, cascata de cache, relatório, minhas-tarefas) onde o `default_scope` do
ActiveRecord não alcança.

## Decisões

### D1 — `position` vira nullable e é zerada no soft-delete (a alternativa quebra a reordenação)

A unicidade de posição é uma **constraint DEFERRABLE** (`uq_*_position UNIQUE (escopo,
position) DEFERRABLE INITIALLY DEFERRED`), exigida pela renumeração em lote de
`ReorderService`, que passa por posições transitoriamente duplicadas dentro da transação.

Um nó soft-deletado que **retivesse** sua `position` colidiria com a renumeração dos irmãos
vivos: `ReorderService` renumera o escopo vivo `0..n-1` (via `default_scope`, só vê vivos),
e se o arquivado ainda ocupasse, digamos, a posição 2, o `UPDATE` de um irmão vivo para 2
violaria o UNIQUE.

Alternativas descartadas:
- **Índice único parcial `WHERE deleted_at IS NULL`**: um índice parcial **não pode** dar
  suporte a uma constraint DEFERRABLE (Postgres só cria constraint deferrable sobre índice
  único total, implícito). Perderíamos o deferimento que a renumeração exige.
- **Renumerar os irmãos no soft-delete** (fechar o buraco): o DELETE físico atual **não**
  renumera — `CrudService#destroy` só destrói e deixa a lacuna, preenchida no próximo
  reorder. Renumerar mudaria o comportamento observável e adicionaria escrita/lock.

**Escolha**: `position` passa a `NULL`able; o soft-delete faz `SET deleted_at = now(),
position = NULL`. `NULL` é isento da constraint UNIQUE (múltiplos `NULL` permitidos), a
constraint DEFERRABLE fica **intacta**, e o comportamento de "deixa a lacuna" é preservado
(o irmão novo entra em `MAX(position)+1` ignorando `NULL`; o reorder só toca vivos).
`assign_next_position` usa `maximum(:position)`, que ignora `NULL` — nada a mudar lá.
**Mora em**: migration (coluna nullable) + `SoftDeleteService` (zera no UPDATE).

### D2 — Índice único de nome vira parcial (nome reusável depois de arquivar)

`index_*_on_*_lower_name` são únicos totais. Com soft-delete, criar um robô "R-014" depois
de arquivar o "R-014" antigo colidiria. Espelhando o que `people.archived_at` fez, viram
**parciais** `WHERE deleted_at IS NULL`. `IdempotentCreate` (que detecta `name_taken` pelo
índice) passa a considerar só os vivos — correto: o nome do arquivado está livre.
**Mora em**: migration (drop + recreate parcial). **Alternativa descartada**: manter total
e bloquear o reuso — punia o usuário por ter arquivado, sem ganho.

### D3 — Cascade de soft-delete na APLICAÇÃO, não por FK (a FK física não dispara sem DELETE)

O cascade de exclusão hoje é FK do banco (`ON DELETE CASCADE`). Sem DELETE físico, ele não
dispara. `Hierarchy::SoftDeleteService` faz o cascade em Ruby, numa transação: arquiva a
subárvore de baixo para cima em coluna (`tasks` → `robots` → `cells` → o nó), com
`update_all(deleted_at: now, position: nil)` por nível (um UPDATE por nível, não N
callbacks — espelha o espírito do D-H6 "um DELETE, não 200 callbacks"). A ordem
baixo→cima não importa para correção (é tudo uma transação), mas mantém os índices coerentes
a cada passo. Cada `update_all` roda **sem** `default_scope` de `deleted_at` no alvo? Não —
usa a relação já escopada por workspace/RLS; itens já arquivados têm `deleted_at` não-nulo e
reescrevê-los é idempotente e inofensivo, mas filtramos `where(deleted_at: nil)` para não
mexer no `deleted_at` original de quem já estava arquivado (preserva o carimbo de quando foi
arquivado). **Mora em**: `Hierarchy::SoftDeleteService`. **Alternativa descartada**:
`before_destroy` no model disparando cascade — `destroy` continuaria físico e bateria na FK
`RESTRICT`; e um `delete_all` se contorna. O serviço explícito é o único ponto.

### D4 — `CrudService#destroy` chama o soft-delete e mantém a auditoria na mesma transação

`destroy` troca `record.destroy!` por `SoftDeleteService.call(record:)`. O bloco de
`audit_destroy!` (hoje log estruturado) e o `cascade_after_destroy` (recompute do pai)
**permanecem na mesma transação** — a semântica "auditoria + recompute atômicos com a
remoção" (D-H6) é preservada, agora sobre soft-delete. O retorno segue `204`. O recompute do
pai passa a enxergar a subárvore arquivada como ausente (via views corrigidas — D5).
**Mora em**: `Hierarchy::CrudService#destroy`.

### D5 — As quatro views de progresso filtram `deleted_at` no lado da hierarquia (senão o arquivado arrasta a média)

As views já filtram `tasks` (`t.deleted_at IS NULL`), mas leem `robots`/`cells`/`projects`
sem filtro. Um robô arquivado, ainda presente na view, entraria na média da célula
(`avg(rwp.value)`) e na contagem crua. As quatro (`robot_weighted_progress`,
`cell_weighted_progress`, `project_weighted_progress`, `subtree_raw_completion`) são
**recriadas** com `AND r.deleted_at IS NULL` / `c.deleted_at IS NULL` / `p.deleted_at IS
NULL` em cada `FROM`/`LEFT JOIN` da hierarquia. Como são `security_invoker`, a recriação
preserva a RLS do invocador. **Mora em**: nova migration `CREATE OR REPLACE VIEW` (+
`structure.sql`). **Consequência**: a cascata de cache (`CascadeRecompute`), que lê essas
views, passa a computar o valor certo sem mudança — ela só precisa achar o `cell_id`/
`project_id` do nó arquivado para saber qual pai recalcular, e o SQL cru dela lê o nó
arquivado de propósito (ver D6).

### D6 — Leitores em SQL cru: filtrar onde se LÊ para exibir/contar, preservar onde se NAVEGA para recomputar

Nem todo SQL cru que toca a hierarquia deve filtrar `deleted_at`. Distinção:

- **Navegação para recompute** (`CascadeRecompute`): `SELECT cell_id FROM robots WHERE id =
  <arquivado>` PRECISA achar o robô arquivado para descobrir qual célula recalcular. Aqui
  **não** se filtra — a linha (soft) ainda existe e é o elo. O valor recalculado já exclui o
  arquivado via views (D5). Só o `UPDATE robots/cells/projects SET progress_cache = ...` do
  próprio nó arquivado é inócuo (ninguém lê o cache de um arquivado).
- **Leitura para exibir/contar** (relatório, minhas-tarefas, dump, reconciliação): PRECISA
  filtrar. `commissioning_report_service` (árvore + tarefas + contagens), `my_tasks/
  list_service` (JOIN robots/cells/projects), `progress/cache_dump` e `progress/
  reconciliation_job` (varrem as três tabelas) ganham `deleted_at IS NULL` nas referências à
  hierarquia. `overview_query`/`hierarchy/overview_service` leem `subtree_raw_completion`, já
  coberto por D5.
- **JOIN de associação em agregador** (`overview_service` `Project.left_joins(:cells)`,
  `project_overview_service` `Cell.left_joins(:robots)`, `search_service`
  `joins(:project)`/`joins(cell: :project)`): o `default_scope` do model **primário**
  filtra, mas o do model **juntado NÃO entra na condição do JOIN** (Rails não injeta). Um
  projeto vivo com uma célula arquivada individualmente ainda contaria a célula. Adiciona-se
  `where(<tabela_juntada>: { deleted_at: nil })` — seguro para LEFT JOIN (linha ausente tem
  `deleted_at` NULL, que satisfaz `IS NULL`, então projetos sem célula continuam aparecendo).
**Mora em**: cada serviço listado. **Cross-check**: como o cascade (D3) arquiva descendentes
junto com o pai, "filho vivo sob pai morto" não ocorre pelo caminho normal; os filtros de
JOIN cobrem o caso de **exclusão individual do filho** e são defesa em profundidade.

### D7 — `default_scope` compõe com o do `WorkspaceScoped` (os dois somam)

`Project`/`Cell`/`Robot` já incluem `WorkspaceScoped` (que tem seu `default_scope` de
tenant). Adicionar `default_scope { where(deleted_at: nil) }` **soma** (Rails encadeia
default_scopes com AND) — exatamente como `Task` faz. `unscoped` continua removendo os dois
(a RLS no banco é a garantia real de tenant, provada com o concern desligado). `ReorderService`
e `IdempotentCreate` usam relações escopadas → passam a ver só vivos automaticamente.
**Mora em**: os três models.

## Onde cada invariante mora

| Invariante | Mora em |
|---|---|
| Nó arquivado some da leitura de domínio | `default_scope` (model) + filtros de SQL cru (D6) |
| Nó arquivado não conta no progresso | Views recriadas (D5, banco) |
| Nome reusável após arquivar | Índice único parcial (banco, D2) |
| Reordenação não colide com arquivado | `position` NULL no soft-delete (banco+serviço, D1) |
| Exclusão não quebra a trilha imutável | Cascade em app troca DELETE por UPDATE (D3/D4) |
| Auditoria + recompute atômicos com a remoção | Transação de `CrudService#destroy` (D4) |
| Isolamento de tenant | RLS forçada (inalterada) |

## Riscos e provas

- **Prova central**: soft-delete de um robô que tem tarefas COM avanços responde `204`
  (hoje daria 500), a linha do robô permanece com `deleted_at` setado, os avanços continuam
  intactos, e o robô some de overview/relatório/minhas-tarefas e para de contar no progresso
  da célula.
- **Prova de reuso de nome**: arquivar "R-014" e criar outro "R-014" na mesma célula →
  `201`, não `409 name_taken`.
- **Prova de reordenação**: arquivar o robô da posição 1 de 3 e reordenar os dois restantes
  → sem violação de UNIQUE.
- **Prova de progresso**: célula com dois robôs (um 100%, um 0%) mostra 50%; arquivar o de
  0% → mostra 100%.
- **Prova de tenant**: soft-delete de nó de outro workspace responde `404` byte-idêntico ao
  de id inexistente (RLS esconde a linha; o serviço não distingue).
