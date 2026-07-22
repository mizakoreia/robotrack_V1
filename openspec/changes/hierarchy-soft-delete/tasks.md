# Tarefas — hierarchy-soft-delete

Pré-requisitos de outras capacidades (não implementar aqui): `commissioning-hierarchy`
(`projects`/`cells`/`robots`, FKs compostas, `CrudService`, `ReorderService`),
`progress-advances` (`tasks.deleted_at` + `task_advances` imutável), `progress-rollup` (as
quatro views e a cascata de cache).

## 1. Esquema: `deleted_at`, índices parciais e views

- [x] 1.1 Migration adicionando `deleted_at timestamptz NULL` a `projects`, `cells` e
  `robots`; tornando `position` nullable nas três; trocando cada índice único de nome
  (`index_projects_on_workspace_lower_name`, `index_cells_on_project_lower_name`,
  `index_robots_on_cell_lower_name`) por versão **parcial** `WHERE deleted_at IS NULL`; e
  criando índice parcial de apoio à leitura viva (`(workspace_id) WHERE deleted_at IS NULL`
  por nível). A constraint DEFERRABLE de posição permanece intacta. (§1.1 — `INSERT` de um
  segundo "R-014" na mesma célula com o primeiro arquivado NÃO pode violar o índice)
- [x] 1.2 Migration `CREATE OR REPLACE VIEW` recriando `robot_weighted_progress`,
  `cell_weighted_progress`, `project_weighted_progress` e `subtree_raw_completion` com
  `deleted_at IS NULL` em cada `FROM`/`LEFT JOIN` de `robots`/`cells`/`projects` (mantendo
  `security_invoker` e o filtro de `tasks` já existente); atualizar `db/structure.sql`.
  (§2.1/§3.2 — um robô arquivado numa célula com um robô a 100% e um a 0% não pode manter a
  média em 50)
- [x] 1.3 Adicionar `default_scope { where(deleted_at: nil) }` a `Project`, `Cell` e `Robot`
  (espelhando `Task`; compõe com o `WorkspaceScoped`). (spec — `Project.all` não pode
  retornar projeto arquivado; `unscoped` continua vendo tudo)
- [x] 1.4 **Verificação:** spec de esquema/model que arquiva um robô e prova: (a)
  `Robot.all` não o traz e `unscoped` traz; (b) criar outro robô com o mesmo nome na célula
  responde criado, não `name_taken`; (c) a view `cell_weighted_progress` da célula muda de
  `50` para `100` ao arquivar o robô de 0%; (d) `position` do arquivado é `NULL`. (cobre
  1.1–1.3)

## 2. Cascade de soft-delete e conversão do `CrudService`

- [ ] 2.1 `Hierarchy::SoftDeleteService.call(record:)` que, numa transação, arquiva a
  subárvore de baixo para cima (`tasks` → `robots` → `cells` → o nó) via `update_all(deleted_at:
  now, position: nil)` filtrando `where(deleted_at: nil)` em cada nível (não reescreve o
  carimbo de quem já estava arquivado), respeitando o escopo de workspace/RLS. Aceita
  `Project`, `Cell` ou `Robot`. (D3 — arquivar projeto marca célula/robô/tarefa; nenhum
  `task_advances` some)
- [ ] 2.2 Converter `Hierarchy::CrudService#destroy` para chamar `SoftDeleteService.call`
  em vez de `record.destroy!`, mantendo `audit_destroy!` e `cascade_after_destroy` (recompute
  do pai) na MESMA transação e o retorno `204`. (D4 — o robô com avanços que hoje dá 500
  passa a responder 204; o progresso do pai é recalculado excluindo a subárvore)
- [ ] 2.3 **Verificação:** spec de serviço/request que exclui um robô COM avanços e prova
  `204` + robô com `deleted_at` + `task_advances` intactos + robô ausente do overview da
  célula + progresso da célula recalculado; e um caso de exclusão de projeto que arquiva a
  subárvore inteira. Incluir cenário cross-tenant → `404` sem arquivar a linha alheia.
  (cobre 2.1–2.2)

## 3. Blindagem dos leitores em SQL cru

- [ ] 3.1 `deleted_at IS NULL` nas referências à hierarquia dos leitores de exibição/contagem
  em SQL cru: `reports/commissioning_report_service` (árvore, tarefas, contagens de status),
  `my_tasks/list_service` (JOIN robots/cells/projects), `progress/cache_dump` e
  `progress/reconciliation_job` (varredura das três tabelas). NÃO filtrar em
  `progress/cascade_recompute` (navega para o pai a recalcular — precisa achar o nó
  arquivado; o valor já exclui via views). (D6 — relatório e minhas-tarefas não podem listar
  robô/tarefa arquivados)
- [ ] 3.2 Filtro de lado juntado nos agregadores por JOIN de associação:
  `hierarchy/overview_service` (`Project.left_joins(:cells)` → `where(cells: { deleted_at:
  nil })`), `hierarchy/project_overview_service` (`Cell.left_joins(:robots)`),
  `hierarchy/search_service` (`joins(:project)`/`joins(cell: :project)`). Seguro para LEFT
  JOIN (`IS NULL` cobre a linha ausente). (D6 — projeto vivo com célula arquivada
  individualmente não pode contá-la; projeto sem células continua aparecendo)
- [ ] 3.3 **Verificação:** spec que, para overview, project-overview, busca, relatório de
  comissionamento e minhas-tarefas, arquiva um nó (robô/célula) e prova sua ausência em cada
  leitura, e que um pai sem filhos vivos ainda aparece (contagem 0), não some. (cobre
  3.1–3.2)

## 4. Verificação transversal e fechamento

- [ ] 4.1 Rodar a suíte de backend dirigida às áreas afetadas (hierarquia, progresso,
  relatório, minhas-tarefas) com 0 falhas, e depois a suíte completa para confirmar ausência
  de regressão. Registrar o número no EXECUCAO.
- [ ] 4.2 Confirmar que o contrato do endpoint de exclusão segue `204` e que nenhuma spec de
  `commissioning-hierarchy`/`progress-rollup` regrediu; `npx --yes @fission-ai/openspec@1.6.0
  validate hierarchy-soft-delete --strict`.
