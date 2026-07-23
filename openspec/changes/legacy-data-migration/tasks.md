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

- [ ] 2.1 Migrations criando `legacy_import_runs` (`workspace_id`, `legacy_owner_uid`,
  `file_sha256`, `backup_path`, `status`, `report` jsonb) e `legacy_id_map`
  (`run_id`, `entity_type`, `legacy_path`, `new_id`) com único `(run_id, legacy_path)`.
  (D-LDM-2, D-LDM-6 — sem `legacy_id_map` o rollback degrada para `pg_restore` do banco
  inteiro; sem `file_sha256` não há como detectar a reimportação da 8.4.)
- [ ] 2.2 Migration adicionando `CHECK (btrim(lower(name)) <> 'não atribuído')` em `people`
  e índice único `(workspace_id, lower(btrim(name)))`. (D11, D-LDM-3 — um `INSERT` por
  `psql` com o nome sentinela tem de ser rejeitado pelo Postgres, não só pelo model.)
- [ ] 2.3 Implementar a etapa de backup do rake: `pg_dump -Fc` para
  `LEGACY_IMPORT_BACKUP_DIR`, gravando `backup_path` e recusando iniciar se o dump falhar
  ou o diretório não for gravável. (D-LDM-6 — diretório somente leitura precisa abortar
  antes da primeira escrita, com `count(*)` de `projects` inalterado.)
- [ ] 2.4 Implementar `rake legacy:rollback[run_id]` removendo por `legacy_id_map` em ordem
  inversa de dependência, preservando `audit_logs` e gravando o próprio rollback na
  auditoria. (D12, D-LDM-6 — 42 robôs importados + 3 criados depois do corte devem
  resultar em exatamente 3 robôs restantes.)
- [ ] 2.5 **Verificação**: spec que importa, cria dado por fora, faz rollback e afirma que
  só o dado do run sumiu e que a auditoria cresceu em 1 entrada. (D-LDM-6 — o modo de
  falha é o rollback apagar dado de produção pós-corte.)

## 3. Pré-processador estrutural (§4.4)

- [ ] 3.1 Implementar em `Legacy::NormalizeExportService` a promoção de
  `workspace.projects` e `workspace.logs` a coleções de topo com `workspaceId`, removendo
  as chaves aninhadas. (§4.4 — busca por `"projects"`/`"logs"` dentro do objeto
  `workspace` do canônico deve não encontrar nada, e 120 logs aninhados viram 120 de topo,
  não 0 e não 240.)
- [ ] 3.2 Implementar no-op para entrada já canônica (`schemaVersion: 1`), emissão de
  `schemaVersion` como primeira chave, atomicidade por temporário+rename, e exigência de
  `ownerUid`. (D-LDM-1 — falha na entrada 2 de 3 não pode deixar arquivo parcial em disco;
  `normalize` duas vezes tem de dar SHA-256 idêntico.)
- [ ] 3.3 Remover o sentinela `"Não Atribuído"` de `workspace.responsibles`, de todo
  `assignees` e de `resp` na normalização (primeira das três camadas de D-LDM-3), e expor
  `rake legacy:normalize[entrada,saida]` com relatório de `migracoes_aplicadas`. (D11,
  §4.4 — `["Não Atribuído","Ana","Bruno"]` sai como `["Ana","Bruno"]`; export já novo
  reporta `0` migrações em vez de reaplicar.)
- [ ] 3.4 **Verificação**: spec que normaliza `raw_nested.json`, valida a saída contra o
  schema, normaliza de novo e compara SHA-256. (D-LDM-1 — prova de execução única sem
  nenhum estado mutável de migração.)

## 4. Núcleo do importador: identidade e idempotência

- [ ] 4.1 Implementar `Legacy::IdDerivation`: UUIDv5 sobre o caminho legado canônico, com a
  regra de caminho para célula/robô sem id (índice do array). (D-LDM-2 — dois robôs
  homônimos na mesma célula precisam gerar ids distintos, não colidir num só.)
- [ ] 4.2 Implementar o wrapper de escrita `INSERT … ON CONFLICT (id) DO NOTHING` com
  contagem de criados vs. pulados e gravação paralela em `legacy_id_map`. (D-LDM-2 — o
  modo de falha é usar `DO UPDATE` e o segundo run sobrescrever edição feita pelo usuário
  depois do corte.)
- [ ] 4.3 Implementar o set explícito de `app.current_workspace_id` por workspace, a recusa
  quando não definido, e a verificação de procedência `ownerUid` do arquivo vs. dono do
  workspace de destino. (D2, D-LDM-1 — chamar o service sem a variável tem de falhar antes
  da primeira escrita, nunca gravar no workspace errado; e é isto que substitui o "só o
  dono" que no legado era runtime.)
- [ ] 4.4 **Verificação**: spec que importa a fixture duas vezes no mesmo banco e afirma
  `criados: 0` no segundo run para os oito tipos de entidade, mais `count(*)` idêntico e
  `updated_at` inalterado num robô renomeado entre os runs. (D-LDM-2 — cenário central
  desta capacidade.)

## 5. Importadores por entidade

- [ ] 5.1 `Legacy::ImportWorkspaceService` + `ImportMembershipsService` — workspace,
  `ownerUid`, nome, e membros ativos com papel `edit`/`view`; **nenhum** convite é
  importado. (§1.1 — o modo de falha é importar convite expirado e criar acesso fantasma.)
- [ ] 5.2 `Legacy::AssigneeResolver` — ponto **único** de criação de `Person`, com trim +
  downcase, filtro do sentinela, colapso de homônimos por caixa e aviso (não colapso) para
  colisão só por acento. (D10, D11, D-LDM-3 — `"João Silva"`/`"joão silva"` viram uma
  `Person`; `"Joao"`/`"João"` viram duas, com aviso no relatório.)
- [ ] 5.3 `Legacy::ImportTaskTemplatesService` — `defaultTasks`, com a regra `appFilters`
  vs. `apps`, precedência do nome novo quando ambos vierem, e preservação de `"Todas"`.
  (§1.4 item 3, D-LDM-4 — dois templates idênticos exceto pelo nome do campo têm de
  produzir linhas idênticas; `"Todas"` virar lista vazia destrói a escolha do usuário.)
- [ ] 5.4 `Legacy::ImportProjectsService` — `Array()` defensivo em `cells` e renumeração de
  `_ord` timestamp para `position` contígua 0-based com desempate estável pela ordem de
  aparição. (§1.4 defensiva, §2.9 — `_ord` `1700…`/`1500…`/`1900…` vira `position`
  `1`/`0`/`2`; `_ord` empatado não pode alternar entre runs.)
- [ ] 5.5 `Legacy::ImportCellsService` + `ImportRobotsService` — `position` pelo índice do
  array, `application` validado contra o enum de §1.2, `Array()` defensivo em `robots` e
  `tasks`. (§1.2, §1.4 — `application: "Paletização"` manda o robô e suas tarefas para
  quarentena sem abortar o run; célula sem `robots` importa com zero filhos.)
- [ ] 5.6 `Legacy::ImportTasksService` — `cat`, `desc`, `weight`, `progress`, `status`,
  `position`, **sem** colunas `resp` e `obs`. (§1.1, `robot-tasks` D-RT-2 — o modo de falha
  é o importador tentar gravar `resp` numa coluna que não existe e derrubar o run inteiro.)
- [ ] 5.7 `Legacy::ImportAdvancesService` + `ImportAuditLogsService` +
  `ImportNotificationsService` — `history` para `task_advances` com `recorded_at` vindo do
  `ts` legado (D8) e `author_name_snapshot` de `byName`; logs de §2.8; notificações de §2.7
  com `read` preservado e `msg` truncado a 500 com aviso. (D8, §4.1 inv. 8 — trocar
  `recorded_at` por `created_at` reescreve a cronologia da trilha; notificação de 501 chars
  não pode violar a constraint nem abortar o run.)
- [ ] 5.8 **Verificação**: spec end-to-end que importa a fixture e afirma a contagem exata
  por tabela, **incluindo os zeros esperados** (projeto sem `cells` = 0 células, robô sem
  `tasks` = 0 tarefas e `progress_cache` 0). (§1.4, §2.1 — o modo de falha é o importador
  engolir silenciosamente um nível inteiro da hierarquia e ninguém notar.)

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
