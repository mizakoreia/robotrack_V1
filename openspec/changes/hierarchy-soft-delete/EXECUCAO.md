# EXECUCAO — hierarchy-soft-delete

Mapa de execução. Escrito ANTES de qualquer código (commit G0). RETOMADA no fim.

## Ponto de partida

Branch empilhada sobre `workspace-settings` (que está PARCIAL: G0–G4 verdes, G5/G6
PAUSADOS por causa DESटA change). Backend-only. Entrega o **soft-delete da hierarquia**
(`projects`/`cells`/`robots`), fechando a tensão **D-H6×D-IMUT** anotada na CONTINUIDADE e
desbloqueando o reset de fábrica (`workspace-settings` G5).

**O bloqueio que originou a change:** `Hierarchy::CrudService#destroy` faz `record.destroy!`
(DELETE físico, cascade por FK). A FK `task_advances → tasks` é `ON DELETE RESTRICT` e a
trilha de avanços é imutável (REVOKE DELETE + trigger). Logo, apagar um robô/célula/projeto
que tenha QUALQUER tarefa com avanço → o cascade bate na FK RESTRICT → **500**. É o caso
normal. `tasks` já resolveu isso para si com soft-delete; esta change estende o padrão para
os três níveis acima e blinda todos os leitores.

Depende de: `commissioning-hierarchy` (as três tabelas, FKs compostas, `CrudService`,
`ReorderService`, `PositionScoped`), `progress-advances` (`tasks.deleted_at`, `task_advances`
imutável), `progress-rollup` (as 4 views `security_invoker` + `CascadeRecompute`).

## RECONCILIAÇÃO COM A REALIDADE (crítico — ler antes de codar)

- **`tasks` é o molde**: `Task` já tem `default_scope { where(deleted_at: nil) }`
  (`app/models/task.rb:37`) e as views já filtram `t.deleted_at IS NULL`. Copio o padrão.
- **`people.archived_at` é o precedente do índice parcial**: a migration de
  `workspace-settings` trocou o índice único de nome de `people` por parcial `WHERE
  archived_at IS NULL`. Faço o análogo para os três nomes de hierarquia com `deleted_at`.
- **Posição é constraint DEFERRABLE, não índice** (`uq_*_position ... DEFERRABLE INITIALLY
  DEFERRED`). Índice parcial NÃO pode dar suporte a constraint deferrable → não dá para
  torná-la parcial. Solução (design D1): `position` vira nullable e o soft-delete a zera
  para `NULL` (isento do UNIQUE). `assign_next_position` usa `maximum(:position)` (ignora
  NULL) — nada a mudar lá. `ReorderService` usa relação escopada (só vivos após o
  default_scope) — passa a renumerar só vivos.
- **As 4 views leem hierarquia SEM filtro de `deleted_at`** (só filtram `tasks`). Inventário
  (agente Explore) confirmou: `robot_weighted_progress` (`FROM robots`),
  `cell_weighted_progress` (`FROM cells` + `JOIN robots`), `project_weighted_progress` (`FROM
  projects` + `JOIN cells`), `subtree_raw_completion` (as três em cada braço do UNION). TODAS
  recriadas no G1. `structure.sql` espelha e precisa ser atualizado.
- **`CascadeRecompute` NÃO deve filtrar `deleted_at`** nos SELECTs de navegação (`SELECT
  cell_id FROM robots WHERE id = <arquivado>`): ele precisa achar o nó arquivado para saber
  qual pai recalcular. O valor recalculado já exclui o arquivado via views (D6). Só os
  leitores de EXIBIÇÃO/CONTAGEM filtram.
- **Leitores de SQL cru a blindar (G3)** — do inventário:
  - Exibição/contagem: `reports/commissioning_report_service` (fetch_tree L70-72, fetch_tasks
    L86-88, fetch_status_counts L116), `my_tasks/list_service` (L90-92), `progress/cache_dump`
    (L21-23), `progress/reconciliation_job` (L62-67).
  - JOIN de associação (o default_scope do model JUNTADO não entra no JOIN — Rails não
    injeta): `hierarchy/overview_service` (`Project.left_joins(:cells)` L29-33),
    `hierarchy/project_overview_service` (`Cell.left_joins(:robots)` L26-31),
    `hierarchy/search_service` (`joins(:project)` L41, `joins(cell: :project)` L52). Filtro
    `where(<juntada>: { deleted_at: nil })`, seguro para LEFT JOIN (`IS NULL` cobre ausente).
  - `overview_query`/`overview_service` que leem `subtree_raw_completion` → cobertos pela
    view corrigida, sem mudança de código.
- **`backup_export_service` já filtra `Task` por `deleted_at`** e carrega `Cell/Robot/Project`
  como relação primária (auto-filtrada pelo default_scope) → nada a fazer lá.
- **Contrato do endpoint NÃO muda**: `DELETE` da hierarquia segue `204`. Frontend intocado.
- **Cross-tenant**: o soft-delete respeita RLS. Nó de outro workspace → `find_by` retorna nil
  (RLS esconde) → `404` byte-idêntico. Nada de novo, mas provado no G2.

## Ordem dos grupos (mapa)

| Grupo | Escopo | Tarefas |
|---|---|---|
| **G1** | Esquema + views + models: migration `deleted_at` nas 3 tabelas, `position` nullable, índices únicos de nome → parciais, índice parcial de leitura viva; migration `CREATE OR REPLACE VIEW` das 4 views com filtro de hierarquia + `structure.sql`; `default_scope` em `Project`/`Cell`/`Robot`; spec de esquema/model | 1.1–1.4 |
| **G2** | Cascade + `CrudService`: `Hierarchy::SoftDeleteService` (arquiva subárvore em transação, zera position), converte `CrudService#destroy` p/ soft-delete mantendo auditoria+recompute na txn; spec do robô-com-avanços → 204, subárvore, cross-tenant 404 | 2.1–2.3 |
| **G3** | Blindagem dos leitores: `deleted_at IS NULL` em relatório/minhas-tarefas/dump/reconciliação (SQL cru de exibição) e filtro de lado juntado em overview/project-overview/busca; spec de ausência em cada leitura + pai sem filho vivo ainda aparece | 3.1–3.3 |
| **G4** | Verificação transversal + fechamento: suíte dirigida (0 falhas) + suíte completa; confirmar contrato 204 e não-regressão de commissioning-hierarchy/progress-rollup; `openspec validate --strict`; CONTINUIDADE | 4.1–4.2 |

## Decisões próprias previstas (detalhe em design.md)

1. **D1 position nullable + zerada no soft-delete** — única forma de manter a constraint
   DEFERRABLE e não colidir com a reordenação dos vivos.
2. **D2 índice de nome parcial** — nome reusável após arquivar (espelha `people`).
3. **D3 cascade em app** — a FK física não dispara sem DELETE; `update_all` por nível.
4. **D5 views recriadas** — senão o arquivado arrasta a média.
5. **D6 filtrar onde se LÊ para exibir, preservar onde se NAVEGA para recomputar** — a
   distinção fina que evita quebrar a cascata de cache.

## Armadilhas previstas

- **`update_all` e `default_scope`**: `Model.update_all` respeita o `where` da relação. Ao
  arquivar, filtrar `where(deleted_at: nil)` para não reescrever o carimbo de quem já estava
  arquivado. E cuidado: `update_all` NÃO dispara o incremento de `lock_version` só se a chave
  vier explícita — mas soft-delete não é edição de conteúdo; deixar `lock_version` quieto
  (não é lido para exclusão).
- **LEFT JOIN + filtro no lado juntado**: usar `IS NULL` (não `= false` nem igualdade), que
  é satisfeito pela linha ausente do LEFT JOIN — assim pai sem filhos continua aparecendo.
- **DatabaseCleaner + DDL**: a migration de view é DDL; em teste, `CREATE OR REPLACE VIEW` na
  migration roda uma vez no schema load, não por exemplo — sem interação com truncation.
- **`structure.sql` desatualizado**: recriar view na migration E regenerar/editar o
  `structure.sql`, senão `db:schema:load` nasce com a view antiga (mesma classe do caveat
  `pg_dump -x` do audit-log, mas aqui é a definição da view, que o dump INCLUI).
- **Ordem de recompute pós-soft-delete**: `CrudService#destroy` captura o pai ANTES (o nó
  soft-deletado ainda existe, então `SELECT ... WHERE id` acha) e recalcula depois — igual ao
  fluxo atual, só que a subárvore agora está arquivada e as views a excluem.

## Baseline (medir no início do G1)

- Suíte backend na branch atual (workspace-settings), `--seed` fixo, número de exemplos e
  falhas conhecidas (benchmarks de carga). Registrar aqui antes de tocar no código.

## Decisões e reconciliações tomadas na execução

- **G1 — reconciliação cross-change (falso positivo do sweep de progresso):** ao rodar a
  regressão do G1, `spec/progress/progress_write_boundary_spec.rb` acusou
  `app/jobs/workspace/backup_export_job.rb:23` (`WorkspaceBackup...update_all(status:
  'failed')`). O sweep é TEXTUAL e a coluna `status` também existe em `workspace_backups`
  (workspace-settings) — não é escrita em `tasks`. Falso positivo LATENTE desde
  `workspace-settings` G4 (`a7d9e3f`), não introduzido por esta change (o arquivo é
  imutável no meu diff). Corrigi o sweep isentando receptores não-tarefa conhecidos
  (`WorkspaceBackup`/`workspace_backups`) na mesma linha, sem afrouxar a detecção de escrita
  crua real em `tasks`. Mantém "varreduras só crescem".
- **G1 — `structure.sql` regenera sozinho:** `schema_format = :sql`; `db:migrate` já
  redumpou o `structure.sql` com as views novas e as colunas `deleted_at`. Não precisou de
  edição à mão (o caveat do audit-log era sobre GRANT/REVOKE, que o dump omite — aqui é
  definição de view/coluna, que o dump inclui).

## RETOMADA

Se a sessão cair no meio: ler este arquivo + `design.md`. Estado por grupo marcado em
`tasks.md` (`- [x]`). O commit `G<n>:` de cada grupo é atômico (aplicar → rspec 0 falhas →
marcar tasks → `openspec validate --strict` → um commit → push `git push origin
HEAD:hierarchy-soft-delete`). Ao fim de cada grupo: resumo pt-BR client-friendly + pedir
autorização antes do próximo.
