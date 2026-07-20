## ADDED Requirements

### Requirement: Backup obrigatório antes de qualquer escrita

O importador SHALL executar `pg_dump -Fc` para `LEGACY_IMPORT_BACKUP_DIR` e registrar o
caminho em `legacy_import_runs.backup_path` antes da primeira escrita. O run MUST recusar
iniciar se o dump falhar ou se o diretório não for gravável.

#### Scenario: diretório de backup não gravável aborta antes de escrever

- **WHEN** `LEGACY_IMPORT_BACKUP_DIR` aponta para um caminho somente leitura e
  `rake legacy:import` é chamado
- **THEN** o run termina com código diferente de zero, nenhuma linha é criada em
  `legacy_import_runs`, e `SELECT count(*) FROM projects` permanece inalterado

#### Scenario: caminho do dump fica registrado no run

- **WHEN** um import bem sucedido conclui
- **THEN** a linha correspondente em `legacy_import_runs` tem `backup_path` apontando para
  um arquivo existente e não vazio, e `file_sha256` com o hash do canônico importado

### Requirement: Rollback por run

`rake legacy:rollback[run_id]` SHALL remover exatamente as linhas criadas por aquele run,
em ordem inversa de dependência, usando `legacy_id_map`, e MUST NOT remover nenhum
registro criado fora dele. Entradas de `audit_logs` MUST NOT ser removidas (D12); o
rollback SHALL gravar no próprio log que ocorreu.

#### Scenario: rollback remove só o que o run criou

- **WHEN** o run `r1` criou 42 robôs, um usuário criou 3 robôs depois do corte, e
  `rake legacy:rollback[r1]` é executado
- **THEN** `SELECT count(*) FROM robots` devolve `3`, e os 3 remanescentes são exatamente
  os criados pelo usuário

#### Scenario: rollback não apaga auditoria e se registra nela

- **WHEN** `rake legacy:rollback[r1]` conclui, tendo o run `r1` importado 120 entradas de
  `audit_logs`
- **THEN** as 120 entradas continuam em `audit_logs`, e uma entrada nova registra o
  rollback com o `run_id`

#### Scenario: rollback de run inexistente é recusado

- **WHEN** `rake legacy:rollback[00000000-0000-0000-0000-000000000000]` é chamado
- **THEN** a tarefa falha sem apagar nada, com mensagem `run desconhecido`

### Requirement: Validação por amostragem de progresso contra o export

`rake legacy:validate_sample` SHALL recalcular o progresso ponderado de §2.1 diretamente
do arquivo canônico, em código independente do domínio, e comparar com o
`progress_cache` do robô importado, para uma amostra determinística de no mínimo 20 robôs.
A diferença tolerada MUST ser zero. A validação MUST NOT depender do sistema legado estar
executável.

#### Scenario: robô de amostra tem progresso idêntico ao calculado do export

- **WHEN** o robô legado no caminho `projects[0].cells[1].robots[2]` tem tarefas
  `(weight 2, progress 50)`, `(weight 1, progress 100)` e `(weight 3, status "N/A")`
- **THEN** o validador calcula `(2*50 + 1*100)/(2+1) = 66.67`, o `progress_cache` do robô
  importado é o mesmo valor, e a diferença reportada é `0`

#### Scenario: amostra é adversarial e tem no mínimo 20 robôs

- **WHEN** `rake legacy:validate_sample` roda sobre um canônico com 42 robôs
- **THEN** a amostra tem ≥20 robôs e inclui obrigatoriamente um robô sem tarefas, um robô
  só com tarefas `N/A`, um robô com pesos diferentes de `1`, um robô com tarefa em
  progresso parcial e o robô com o maior número de tarefas do arquivo

#### Scenario: casos-limite de §2.1 conferem

- **WHEN** a amostra inclui um robô sem nenhuma tarefa e um robô cujas 4 tarefas são todas
  `N/A`
- **THEN** o validador espera `0` para o primeiro e `100` para o segundo, e o
  `progress_cache` importado bate com os dois

#### Scenario: divergência de um único robô reprova o run inteiro

- **WHEN** 19 dos 20 robôs da amostra batem e um difere em `0.01`
- **THEN** a tarefa termina com código diferente de zero, lista o `legacy_path` do robô
  divergente com os dois valores, e recomenda `rake legacy:rollback[run_id]`

#### Scenario: amostra é reprodutível entre execuções

- **WHEN** `rake legacy:validate_sample` roda duas vezes sobre o mesmo canônico e o mesmo
  banco
- **THEN** o conjunto de robôs amostrados é idêntico nas duas execuções

### Requirement: Dry-run que não escreve

O importador SHALL oferecer `rake legacy:import[arquivo,dry_run]` que percorre o arquivo
inteiro, produz a contagem por tipo de entidade e a lista de quarentena prevista, e MUST
NOT executar nenhuma escrita nem exigir backup.

#### Scenario: dry-run não cria nada e prevê a quarentena

- **WHEN** o dry-run roda sobre um canônico com 3 tarefas de `status` inválido
- **THEN** o relatório lista as 3 tarefas com seus `legacy_path`, reporta as contagens por
  entidade, e `SELECT count(*)` em todas as tabelas de domínio permanece inalterado

### Requirement: Formato de backup compartilhado com `workspace-settings`

`config/legacy_export_v1.schema.json` SHALL ser o contrato único do arquivo
`RoboTrack_Database.json`, versionado por `schemaVersion`, consumido por esta capacidade e
produzido pelo exportador de §3.11 (`workspace-settings`). Um arquivo produzido pelo
exportador SHALL ser importável sem passar por `legacy:normalize`.

#### Scenario: round-trip export → import é aceito sem normalização

- **WHEN** `workspace-settings` exporta um workspace com 2 projetos e 11 robôs e o arquivo
  resultante é passado diretamente para `rake legacy:import`
- **THEN** a validação de schema passa, o import cria 2 projetos e 11 robôs, e nenhuma
  chamada a `legacy:normalize` é necessária

#### Scenario: schemaVersion desconhecido é recusado

- **WHEN** o arquivo declara `schemaVersion: 2`
- **THEN** o import falha antes de qualquer escrita com mensagem citando a versão
  suportada `1`

#### Scenario: arquivo sem schemaVersion é tratado como bruto

- **WHEN** o arquivo não declara `schemaVersion`
- **THEN** o import recusa e instrui a rodar `rake legacy:normalize` primeiro

### Requirement: Relatório do run auditável

Todo run SHALL produzir um relatório persistido contendo contagens de criados, pulados por
conflito e em quarentena por tipo de entidade, os avisos de divergência, e o SHA-256 do
arquivo importado. Reimportar um arquivo de hash diferente para um workspace já importado
SHALL exigir confirmação explícita.

#### Scenario: relatório distingue criado de pulado

- **WHEN** o primeiro run cria 42 robôs e o segundo run sobre o mesmo arquivo termina
- **THEN** o relatório do primeiro reporta `robots: criados 42, pulados 0` e o do segundo
  `robots: criados 0, pulados 42`

#### Scenario: arquivo diferente sobre workspace já importado exige --force

- **WHEN** um segundo arquivo, com SHA-256 diferente do registrado, é importado para um
  workspace que já tem um run concluído, sem a flag `--force`
- **THEN** o run é recusado antes de escrever, citando os dois hashes
