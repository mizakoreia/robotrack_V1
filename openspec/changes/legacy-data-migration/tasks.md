# Tarefas — legacy-data-migration

> `[BLOQUEADO: export]` marca tarefa que **não é executável** sem o arquivo real
> `RoboTrack_Database.json`, que não está no repositório. As demais rodam contra a
> fixture sintética da tarefa 1.2.

## 1. Contrato de arquivo e insumo

- [x] 1.1 Escrever `backend/config/legacy_export_v1.schema.json` (JSON Schema) cobrindo
  workspace, `responsibles`, `defaultTasks`, `projects`/`cells`/`robots`/`tasks`/`history`,
  `logs` e `members`, com `schemaVersion` obrigatório no topo e os enums de §1.1/§1.2
  fechados. (§1.1, D-LDM-8 — um arquivo com `application: 42` é rejeitado citando o
  caminho `projects[1].cells[0].robots[3]`, não com `NoMethodError` no meio do run.)
- [x] 1.2 Escrever as duas fixtures: `canonical_v1.json` cobrindo projeto sem `cells`,
  célula sem `robots`, robô sem `tasks`, `resp: "Não Atribuído"`, `assignees: []` com
  `resp` preenchido, `obs` com e sem histórico, template com `apps` e com `appFilters`,
  `"Todas"`, dois robôs homônimos na mesma célula, `status` inválido, `progress: 150`,
  `Concluído` com `progress: 80`; e `raw_nested.json` no formato antigo de §4.4, sem
  `schemaVersion`. (§1.4, §4.4, D-LDM-7 — se um cenário da spec não tiver dado
  correspondente aqui, o teste passa vazio e o defeito só aparece no corte.)
- [x] 1.3 **Verificação**: spec que valida `canonical_v1.json` contra o schema e exige que
  `raw_nested.json` **falhe** a validação; registrar no `design.md` de
  `workspace-settings` o acordo de que §3.11 emite este mesmo schema. (§3.11, D-LDM-8 —
  schema que aceita as duas fixtures não é schema; e os dois lados inventando formato
  próprio só quebraria no round-trip da 8.5.)
      *(ENTREGUE — `spec/legacy/schema_contract_spec.rb` (3/3): canônico passa, bruto sem
      `schemaVersion` falha, `application: 42` (tipo) é pego citando o caminho.
      DECISÃO DE RECONCILIAÇÃO (registrada no EXECUCAO): o schema valida ESTRUTURA+TIPOS+
      `schemaVersion`, mas NÃO fecha os value-enums de application/status nem a faixa de
      progress — porque esses VALORES ruins (application 'Paletização', status inválido,
      progress 150) são casos de QUARENTENA do import (D-LDM-7) e precisam passar o schema
      pra serem quarentenados; fechá-los aqui contradiria 5.5/6.4. Notas técnicas: sem
      `$schema`/`$id` (a gem json-schema só traz a meta-schema draft-04) e `use_multi_json
      = false` (MultiJSON manglava o UTF-8). DIVERGÊNCIA com workspace-settings: o backup
      de §3.11 hoje emite `schemaVersion: 2` (fixture `roboTrack_database_v2.json`, campo
      `advances`), enquanto o canônico legado é v1 (`history`). O alinhamento real das duas
      pontas é exercido no round-trip da 8.5; não editei o design de workspace-settings
      (change completa) — a divergência fica anotada aqui.)*

## 2. Infraestrutura de run, backup e rollback

- [x] 2.1 Migrations criando `legacy_import_runs` (`workspace_id`, `legacy_owner_uid`,
  `file_sha256`, `backup_path`, `status`, `report` jsonb) e `legacy_id_map`
  (`run_id`, `entity_type`, `legacy_path`, `new_id`) com único `(run_id, legacy_path)`.
  (D-LDM-2, D-LDM-6 — sem `legacy_id_map` o rollback degrada para `pg_restore` do banco
  inteiro; sem `file_sha256` não há como detectar a reimportação da 8.4.)
      *(ENTREGUE — `20260724110001_create_legacy_import_infrastructure`. RECONCILIAÇÃO: o
      `schema_guard` exige de TODA tabela de domínio `workspace_id NOT NULL` + índice
      liderado por `workspace_id` + FORCE RLS + policy `tenant_isolation`. `legacy_id_map`
      (spec: só `run_id`) reprovaria — carrega `workspace_id` DENORMALIZADO do run. Ambas
      com RLS `robotrack_app` (runs: SELECT/INSERT/UPDATE; map: SELECT/INSERT append-only).
      `status` CHECK inclui `rolled_back`. Índice `(workspace_id, file_sha256)` serve a 8.4.
      Verificação: `schema_guard_spec` cobre as duas automaticamente — 0 falhas.)*
- [x] 2.2 Migration adicionando `CHECK (btrim(lower(name)) <> 'não atribuído')` em `people`
  e índice único `(workspace_id, lower(btrim(name)))`. (D11, D-LDM-3 — um `INSERT` por
  `psql` com o nome sentinela tem de ser rejeitado pelo Postgres, não só pelo model.)
      *(RECONCILIADA — JÁ EXISTE no banco: `people_name_not_sentinel CHECK` e
      `index_people_on_workspace_id_and_normalized_name UNIQUE` (structure.sql:725,1570).
      A camada 3 de D-LDM-3 já vale; a prova crua fica em 7.2.)*
- [x] 2.3 Implementar a etapa de backup do rake: `pg_dump -Fc` para
  `LEGACY_IMPORT_BACKUP_DIR`, gravando `backup_path` e recusando iniciar se o dump falhar
  ou o diretório não for gravável. (D-LDM-6 — diretório somente leitura precisa abortar
  antes da primeira escrita, com `count(*)` de `projects` inalterado.)
      *(ENTREGUE — `Legacy::BackupService` (`app/services/legacy/backup_service.rb`): valida
      diretório definido/existente/gravável ANTES de qualquer `pg_dump`, roda `pg_dump -Fc`
      com as credenciais da conexão e grava `backup_path`. `backup_spec` prova as 3 recusas
      (o `pg_dump` só roda no caminho feliz). O teste de dir não-gravável fica `pending`
      quando a suíte roda como root (o `access()` ignora o bit de permissão).)*
- [x] 2.4 Implementar `rake legacy:rollback[run_id]` removendo por `legacy_id_map` em ordem
  inversa de dependência, preservando `audit_logs` e gravando o próprio rollback na
  auditoria. (D12, D-LDM-6 — 42 robôs importados + 3 criados depois do corte devem
  resultar em exatamente 3 robôs restantes.)
      *(ENTREGUE — `rake legacy:rollback[run_id]` + `Legacy::RollbackService`. RECONCILIAÇÃO
      CRÍTICA (ver EXECUCAO §G2): o porte tem DUAS tabelas append-only imutáveis por
      REVOKE+trigger — `task_advances` (D-IMUT) e `audit_logs` (D12). Uma tarefa importada
      com avanço legado é travada pela FK RESTRICT do avanço; DELETE físico é impossível (o
      mesmo muro que fez o factory-reset ARQUIVAR). Logo: a HIERARQUIA do run é ARQUIVADA
      (`deleted_at`, só os ids mapeados — filho pós-corte sobrevive), as FOLHAS sem trava
      (task_assignees/notifications/task_templates/memberships/people) são DELETADAS, e
      `task_advances`/`audit_logs` importados NÃO são tocados. "N robôs restantes" = N
      VISÍVEIS. A entrada de auditoria exigiu um `event_type` novo `legacy_rollback`
      (migration `20260724110002` estende o CHECK; model/locale/snapshot atualizados).)*
- [x] 2.5 **Verificação**: spec que importa, cria dado por fora, faz rollback e afirma que
  só o dado do run sumiu e que a auditoria cresceu em 1 entrada. (D-LDM-6 — o modo de
  falha é o rollback apagar dado de produção pós-corte.)
      *(ENTREGUE — `rollback_spec` (verde): monta um run à mão (hierarquia + folhas + 1
      avanço legado, tudo em `legacy_id_map`) + dado pós-corte não mapeado; após o rollback
      afirma hierarquia do run arquivada, folhas deletadas, avanço legado INTOCADO, TODO o
      dado pós-corte preservado e `audit_logs` +1 com `event_type = legacy_rollback`.)*

## 3. Pré-processador estrutural (§4.4)

- [x] 3.1 Implementar em `Legacy::NormalizeExportService` a promoção de
  `workspace.projects` e `workspace.logs` a coleções de topo com `workspaceId`, removendo
  as chaves aninhadas. (§4.4 — busca por `"projects"`/`"logs"` dentro do objeto
  `workspace` do canônico deve não encontrar nada, e 120 logs aninhados viram 120 de topo,
  não 0 e não 240.)
- [x] 3.2 Implementar no-op para entrada já canônica (`schemaVersion: 1`), emissão de
  `schemaVersion` como primeira chave, atomicidade por temporário+rename, e exigência de
  `ownerUid`. (D-LDM-1 — falha na entrada 2 de 3 não pode deixar arquivo parcial em disco;
  `normalize` duas vezes tem de dar SHA-256 idêntico.)
- [x] 3.3 Remover o sentinela `"Não Atribuído"` de `workspace.responsibles`, de todo
  `assignees` e de `resp` na normalização (primeira das três camadas de D-LDM-3), e expor
  `rake legacy:normalize[entrada,saida]` com relatório de `migracoes_aplicadas`. (D11,
  §4.4 — `["Não Atribuído","Ana","Bruno"]` sai como `["Ana","Bruno"]`; export já novo
  reporta `0` migrações em vez de reaplicar.)
      *(ENTREGUE — `Legacy::NormalizeExportService` + `rake legacy:normalize[entrada,saida]`.
      Idempotência SEM canonicalização profunda: só as chaves de topo e de `workspace` têm
      ordem fixada; o conteúdo aninhado passa preservando a ordem (`merge` no lugar), então
      `raw→a→b` dá SHA-256 idêntico. `scrub_task` só toca `assignees`/`resp` que a tarefa
      DECLARA (não injeta chave nova). Relatório: `migracoes_aplicadas` (promoções
      estruturais), `sentinela_removido`, `entrada_ja_canonica`.)*
- [x] 3.4 **Verificação**: spec que normaliza `raw_nested.json`, valida a saída contra o
  schema, normaliza de novo e compara SHA-256. (D-LDM-1 — prova de execução única sem
  nenhum estado mutável de migração.)
      *(ENTREGUE — `normalize_spec` (9 ex., verde): promoção estrutural 2 migrações,
      formato-já-de-topo 0 migrações, `schemaVersion` 1ª chave, saída valida no schema,
      `ownerUid` ausente aborta / propagado, sentinela sai de responsibles+assignees+resp,
      log sem `ts` aborta SEM deixar saída nem temporário (atomicidade), e SHA-256 de
      `a.json`==`b.json` com a 2ª rodada reportando `entrada_ja_canonica: true`.)*

## 4. Núcleo do importador: identidade e idempotência

- [x] 4.1 Implementar `Legacy::IdDerivation`: UUIDv5 sobre o caminho legado canônico, com a
  regra de caminho para célula/robô sem id (índice do array). (D-LDM-2 — dois robôs
  homônimos na mesma célula precisam gerar ids distintos, não colidir num só.)
      *(ENTREGUE — `Legacy::IdDerivation`. `NAMESPACE` fixo (congelado — mudá-lo reescreve
      todos os ids). `ref(obj,index)` = id-se-houver-senão-índice; construtores de caminho
      por entidade + açúcar `<ent>_id`. Prova: homônimos R05 (id `r-2` vs índice) → ids
      distintos; `person_id` colapsa "João Silva"/"joão silva" por downcase.)*
- [x] 4.2 Implementar o wrapper de escrita `INSERT … ON CONFLICT (id) DO NOTHING` com
  contagem de criados vs. pulados e gravação paralela em `legacy_id_map`. (D-LDM-2 — o
  modo de falha é usar `DO UPDATE` e o segundo run sobrescrever edição feita pelo usuário
  depois do corte.)
      *(ENTREGUE — `Legacy::Writer.insert` via `insert_all(unique_by: :id)` = `ON CONFLICT
      (id) DO NOTHING` (o `unique_by: :id` é obrigatório: sem ele o insert_all esbarra na
      unique DEFERÍVEL de posição como árbitro). Conta criados/pulados e grava `legacy_id_map`
      só dos criados (2º run cria 0 → 0 linhas de mapa novas).)*
- [x] 4.3 Implementar o set explícito de `app.current_workspace_id` por workspace, a recusa
  quando não definido, e a verificação de procedência `ownerUid` do arquivo vs. dono do
  workspace de destino. (D2, D-LDM-1 — chamar o service sem a variável tem de falhar antes
  da primeira escrita, nunca gravar no workspace errado; e é isto que substitui o "só o
  dono" que no legado era runtime.)
      *(ENTREGUE — `Legacy::ImportContext`: `with_workspace` abre o Tenant e verifica a
      procedência JÁ DENTRO (runs anteriores são RLS-escapados); `require_context!` (chamado
      pelo Writer) recusa escrever sem contexto. RECONCILIAÇÃO: o mapeamento ownerUid-Firebase
      → user Rails não é definido nesta change; a procedência aqui é a COERÊNCIA entre runs do
      mesmo workspace (um 2º arquivo de outro ownerUid é recusado) — o par com o sha256 da 8.4.)*
- [x] 4.4 **Verificação**: spec que importa a fixture duas vezes no mesmo banco e afirma
  `criados: 0` no segundo run para os oito tipos de entidade, mais `count(*)` idêntico e
  `updated_at` inalterado num robô renomeado entre os runs. (D-LDM-2 — cenário central
  desta capacidade.)
      *(ENTREGUE — `import_core_spec` (7 ex., verde) prova o MECANISMO sobre projeto→célula→
      robô (o caminho que carrega FK + `updated_at`): 2º run cria 0 / pula 3, robô renomeado
      no 2º run mantém o nome do 1º (DO NOTHING, não DO UPDATE) e `updated_at` inalterado,
      `count(*)` idêntico. RECONCILIAÇÃO: a varredura fim-a-fim das 8 entidades com contagem
      por tabela é a spec 5.8 (precisa dos importadores de G5) — aqui está o mecanismo.)*

## 5. Importadores por entidade

> **G5 — RECONCILIAÇÃO (registrada no EXECUCAO §G5).** Os "8 services" de 5.1/5.3-5.7 são
> as SEÇÕES do orquestrador `Legacy::ImportService` (métodos privados por entidade), não 8
> classes — o que os specs verificam é a contagem por tabela e o relatório. `AssigneeResolver`
> (5.2) e `StatusDerivation` (§2.2) ficam à parte (estado/regra próprios). Duas reconciliações
> com a realidade do schema: (a) **membership NÃO é criada** — a coluna exige `user_id` Rails e
> o mapa ownerUid-Firebase→user não existe nesta change (4.3); os membros entram como PESSOAS.
> (b) **homônimos na mesma célula** — o schema força `UNIQUE (cell_id, lower(name))` (D-H8), que
> contradiz "duas linhas". Não afrouxamos nem perdemos o robô: DESAMBIGUAMOS o nome do colidente
> (`R05`→`R05 (2)`) determinísticamente + aviso `nome_desambiguado`. O id vem do CAMINHO, então
> é idempotente. (A cascata/obs/quarentena de §1.4 vivem no mesmo caminho — as provas por-regra
> são G6.)

- [x] 5.1 `Legacy::ImportWorkspaceService` + `ImportMembershipsService` — workspace,
  `ownerUid`, nome, e membros ativos com papel `edit`/`view`; **nenhum** convite é
  importado. (§1.1 — o modo de falha é importar convite expirado e criar acesso fantasma.)
      *(ENTREGUE como `import_workspace` (nome) + `import_people_roster` (membros→pessoas).
      Nenhum convite/membership fabricado — ver reconciliação (a).)*
- [x] 5.2 `Legacy::AssigneeResolver` — ponto **único** de criação de `Person`, com trim +
  downcase, filtro do sentinela, colapso de homônimos por caixa e aviso (não colapso) para
  colisão só por acento. (D10, D11, D-LDM-3 — `"João Silva"`/`"joão silva"` viram uma
  `Person`; `"Joao"`/`"João"` viram duas, com aviso no relatório.)
      *(ENTREGUE — `Legacy::AssigneeResolver` memoizado; id do caminho usa o ws LEGADO, a
      linha usa o ws de DESTINO. Aviso `homonimo_por_acento` via `I18n.transliterate`.)*
- [x] 5.3 `Legacy::ImportTaskTemplatesService` — `defaultTasks`, com a regra `appFilters`
  vs. `apps`, precedência do nome novo quando ambos vierem, e preservação de `"Todas"`.
  (§1.4 item 3, D-LDM-4 — dois templates idênticos exceto pelo nome do campo têm de
  produzir linhas idênticas; `"Todas"` virar lista vazia destrói a escolha do usuário.)
      *(ENTREGUE — `import_templates`/`template_filters`: appFilters vence apps, aviso
      `app_filters_divergentes`, `"Todas"` preservado, valor fora do enum → quarentena.)*
- [x] 5.4 `Legacy::ImportProjectsService` — `Array()` defensivo em `cells` e renumeração de
  `_ord` timestamp para `position` contígua 0-based com desempate estável pela ordem de
  aparição. (§1.4 defensiva, §2.9 — `_ord` `1700…`/`1500…`/`1900…` vira `position`
  `1`/`0`/`2`; `_ord` empatado não pode alternar entre runs.)
      *(ENTREGUE — `import_projects_tree`/`renumber`: sort estável por `[_ord, aparição]`.)*
- [x] 5.5 `Legacy::ImportCellsService` + `ImportRobotsService` — `position` pelo índice do
  array, `application` validado contra o enum de §1.2, `Array()` defensivo em `robots` e
  `tasks`. (§1.2, §1.4 — `application: "Paletização"` manda o robô e suas tarefas para
  quarentena sem abortar o run; célula sem `robots` importa com zero filhos.)
      *(ENTREGUE — `import_cells`/`import_robots`: `application` fora do enum → quarentena do
      robô (e suas tarefas nem são visitadas); `array_of` trata cells/robots null/ausente.)*
- [x] 5.6 `Legacy::ImportTasksService` — `cat`, `desc`, `weight`, `progress`, `status`,
  `position`, **sem** colunas `resp` e `obs`. (§1.1, `robot-tasks` D-RT-2 — o modo de falha
  é o importador tentar gravar `resp` numa coluna que não existe e derrubar o run inteiro.)
      *(ENTREGUE — `import_tasks`/`prepare_task`: só as 6 colunas; `resp`/`obs` nunca gravados.)*
- [x] 5.7 `Legacy::ImportAdvancesService` + `ImportAuditLogsService` +
  `ImportNotificationsService` — `history` para `task_advances` com `recorded_at` vindo do
  `ts` legado (D8) e `author_name_snapshot` de `byName`; logs de §2.8; notificações de §2.7
  com `read` preservado e `msg` truncado a 500 com aviso. (D8, §4.1 inv. 8 — trocar
  `recorded_at` por `created_at` reescreve a cronologia da trilha; notificação de 501 chars
  não pode violar a constraint nem abortar o run.)
      *(ENTREGUE — `import_advances` (history→task_advances, recorded_at do `ts`; logs em
      `audit_logs` via `insert_all unique_by:[ts,id]` pela PK composta particionada);
      `import_notifications` (resolve destinatário/ator, `read`/`read_at` coerentes, `msg`
      truncada a 500 com aviso `msg_truncada`). obs→avanço legado é 6.2.)*
- [x] 5.8 **Verificação**: spec end-to-end que importa a fixture e afirma a contagem exata
  por tabela, **incluindo os zeros esperados** (projeto sem `cells` = 0 células, robô sem
  `tasks` = 0 tarefas e `progress_cache` 0). (§1.4, §2.1 — o modo de falha é o importador
  engolir silenciosamente um nível inteiro da hierarquia e ninguém notar.)
      *(ENTREGUE — `import_end_to_end_spec` (4 ex., verde): 4 projetos / 3 células / 4 robôs /
      8 tarefas / 4 pessoas / 3 responsáveis / 4 avanços / 4 templates / 1 log / 1 notificação;
      zeros de p-3/p-4 (0 células) e r-2 (0 tarefas, `progress_cache` 0); homônimo colapsado
      (João com 2 responsáveis); sentinela → 0 pessoas; quarentena (app/progress/status/obs) e
      2º run cria 0.)*

## 6. As três regras de §1.4

- [ ] 6.1 Implementar a cascata de responsáveis com a precedência escrita, incluindo o caso
  `assignees: []` **parando** a cascata, e a gravação em `task_assignees` por `person_id`.
  (§1.4 item 1, D-LDM-4 — `assignees: []` com `resp: "Maria"` importa com **zero**
  responsáveis; cair para `resp` ressuscita quem o usuário removeu.)
- [ ] 6.2 Implementar a conversão de `obs` em entrada `legacy` no contrato de
  `progress-advances` (`by NULL`, `"(nota anterior)"`, `0→0`, `legacy: true`), com
  `recorded_at` derivado de `_updatedAt`/`exportedAt` e **nunca** de `Time.now`.
  (§1.4 item 2, D-LEG de `progress-advances` — dois runs em dias diferentes precisam
  produzir `recorded_at` idêntico, senão o UUIDv5 do avanço não é estável e a 4.4 quebra.)
- [ ] 6.3 Implementar o descarte de `obs` quando `history` já tem entradas
  (`obs_descartado_historico_presente`) e a regra de status↔progresso incoerentes, com
  `progress` como fonte de verdade e `status` derivado por §2.2. (§1.4 item 2, §2.2,
  D-LDM-7 — `Concluído` com `progress: 80` importa como `Em Andamento` + 80, nem
  quarentena nem `progress: 100`.)
- [ ] 6.4 Implementar a quarentena genérica (campo, valor bruto, `legacy_path`, motivo) sem
  relaxar nenhuma constraint nem criar valor de enum novo. (D-LDM-7 — `progress: 150` não
  vira `100`: a tarefa não entra e as tarefas irmãs entram normalmente.)
- [ ] 6.5 **Verificação**: um spec por regra de §1.4, cada um exercitando o caminho
  positivo **e** o negativo da fixture. (§1.4 — o erro histórico é testar só o caminho
  feliz das três regras e descobrir o resto em produção.)

## 7. Prova do sentinela (D11)

- [ ] 7.1 Spec que importa a fixture (sentinela presente em `responsibles`, em `assignees`
  e em `resp`) e afirma `count(*) FROM people WHERE btrim(lower(name)) = 'não atribuído'`
  = `0`, mais a tarefa com `resp: "Não Atribuído"` com zero linhas em `task_assignees` e
  contagem de `people` do workspace inalterada. (D11 — a armadilha é o resolver criar a
  pessoa a partir de qualquer uma das três origens.)
- [ ] 7.2 **Verificação**: spec que tenta `INSERT` direto do sentinela por SQL cru,
  contornando o model, e exige violação de CHECK. (D-LDM-3 — prova de que a defesa está no
  banco; a camada Ruby sozinha se contorna por `rails console`.)

## 8. Validação, dry-run e corte

- [ ] 8.1 Implementar `Legacy::SampleValidator` recalculando §2.1 (ponderado, ignorando
  `N/A`; sem tarefas = 0; só `N/A` = 100) em Ruby puro a partir do JSON, sem ActiveRecord.
  (§2.1, D15, D-LDM-5 — se o validador reutilizar o código do domínio, ele não prova nada
  sobre a tradução, só que o código concorda consigo mesmo.)
- [ ] 8.2 Implementar a seleção determinística e adversarial da amostra (≥20 robôs,
  obrigatoriamente com sem-tarefas, só-`N/A`, pesos ≠ 1, parcial e o de maior número de
  tarefas) e `rake legacy:validate_sample` com tolerância zero. (D-LDM-5 — amostra
  aleatória tende a pegar 20 robôs `Pendente` a 0% e passar sem medir nada.)
- [ ] 8.3 Implementar `rake legacy:import[arquivo,dry_run]` que conta e prevê a quarentena
  sem escrever e sem exigir backup, e o relatório persistido em `report` jsonb com
  criados/pulados/quarentena por entidade. (D-LDM-5 — dry-run que abre transação e faz
  rollback ainda segura locks pela janela inteira; este não escreve.)
- [ ] 8.4 Implementar a recusa de reimportar arquivo com `file_sha256` diferente para um
  workspace já importado, exigindo `--force` e citando os dois hashes. (D-LDM-2 —
  reexportar depois de reordenar arrays produz ids diferentes e duplicaria a hierarquia
  inteira em silêncio.)
- [ ] 8.5 Escrever o runbook de corte em `delivery-and-observability` (ordem normalize →
  schema → dry-run → backup → import → validate → 2º run, com o gatilho de rollback) e o
  spec de round-trip consumindo um arquivo do exportador de §3.11 direto no
  `legacy:import`, sem `normalize`. (§3.11, D-LDM-6, D-LDM-8 — sem runbook o rollback é
  decidido sob pressão às 3h; e o formato divergente entre as duas pontas só apareceria no
  corte.)
- [ ] 8.6 **[BLOQUEADO: export]** Rodar `normalize` + validação de schema + dry-run sobre o
  `RoboTrack_Database.json` real e registrar contagens e quarentena prevista. (§1.4 — o
  volume e a sujeira reais são desconhecidos; é esta tarefa que dimensiona a janela de
  manutenção e revela quantos workspaces o arquivo contém.)
- [ ] 8.7 **[BLOQUEADO: export]** **Verificação de corte**: import real com backup,
  `validate_sample` com diferença zero em ≥20 robôs, e segunda execução provando
  `criados: 0`. (D-LDM-2, D-LDM-5 — é o critério de aceite do corte; qualquer divergência
  dispara `rake legacy:rollback[run_id]` e volta ao passo 8.6.)
