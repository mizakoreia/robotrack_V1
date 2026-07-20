# workspace-backup-export

## ADDED Requirements

### Requirement: Exportar backup como `RoboTrack_Database.json`

O sistema SHALL expor `POST /api/v1/workspace/backups`, que produz um arquivo JSON com o
estado completo do workspace corrente e o entrega ao cliente com o nome literal
`RoboTrack_Database.json`, registrando uma linha em `workspace_backups` com
`id`, `workspace_id`, `checksum`, `counts` e `status` (§3.11).

#### Scenario: download tem o nome de arquivo da especificação
- **WHEN** um usuário `owner` aciona "Exportar backup" no painel Utilitários
- **THEN** a resposta traz `Content-Disposition: attachment; filename="RoboTrack_Database.json"`
- **AND** `Content-Type` é `application/json`

#### Scenario: exportar registra a prova do backup
- **WHEN** o export do workspace `WS-1` termina com sucesso
- **THEN** existe uma linha em `workspace_backups` com `workspace_id = WS-1`,
  `status = "completed"` e `checksum` igual ao sha256 do payload sem a chave `_rt`
- **AND** o `backup_id` é devolvido no corpo da resposta

### Requirement: Formato superset aditivo do legado, versionado

O sistema SHALL serializar o backup no esqueleto aninhado do formato legado
(workspace → `projects[]` → `cells[]` → `robots[]` → `tasks[]`), preservando todas as
chaves legadas com a mesma semântica, e SHALL acrescentar o envelope `_rt` e os campos
nativos exigidos por D1, D8 e D10 (D-EXP).

#### Scenario: envelope de topo declara a versão do formato
- **WHEN** um backup é gerado
- **THEN** a raiz do JSON contém `_rt.schemaVersion = 2`, `_rt.exportedAt` em ISO 8601,
  `_rt.workspaceId` com o uuid do workspace, `_rt.counts` e `_rt.checksum`

#### Scenario: tarefa carrega nomes e ids lado a lado
- **WHEN** uma tarefa tem duas pessoas responsáveis, `Ana` (uuid `P-1`) e `Bruno` (uuid `P-2`)
- **THEN** o objeto da tarefa no JSON contém `"assignees": ["Ana","Bruno"]`
- **AND** contém `"assigneeIds": ["P-1","P-2"]`

#### Scenario: avanços carregam os dois timestamps de D8
- **WHEN** um avanço foi registrado offline às `2026-03-01T08:00:00Z` e persistido pelo
  servidor às `2026-03-01T11:30:00Z`
- **THEN** a entrada correspondente em `advances` contém
  `"recordedAt": "2026-03-01T08:00:00Z"` e `"createdAt": "2026-03-01T11:30:00Z"`

#### Scenario: chaves são serializadas em ordem estável
- **WHEN** o mesmo workspace, sem alterações, é exportado duas vezes
- **THEN** os dois payloads são idênticos byte a byte, desconsiderando `_rt.exportedAt`

### Requirement: Conteúdo completo e isolado por workspace

O sistema SHALL incluir no backup todos os projetos, células, robôs, tarefas, avanços,
templates, pessoas, memberships, convites, notificações e registros de auditoria do
workspace corrente, e SHALL não incluir nenhum dado de outro workspace (§3.11, D2).

#### Scenario: workspace com 3 projetos produz JSON com os 3
- **WHEN** o workspace `WS-1` tem os projetos `Linha A`, `Linha B` e `Linha C` e é exportado
- **THEN** `projects` tem exatamente 3 elementos, com os nomes `Linha A`, `Linha B` e `Linha C`
- **AND** `_rt.counts.projects` é `3`

#### Scenario: auditoria vai junto no backup
- **WHEN** o workspace `WS-1` tem 47 registros de auditoria e é exportado
- **THEN** a coleção de topo `auditLogs` tem 47 elementos
- **AND** `_rt.counts.auditLogs` é `47`

#### Scenario: dado de outro tenant não vaza para o arquivo
- **WHEN** existem 5 projetos em `WS-2` e o usuário exporta `WS-1`, que tem 3
- **THEN** nenhum id, nome ou e-mail pertencente a `WS-2` aparece no arquivo
- **AND** a consulta de export roda sob `app.current_workspace_id = WS-1`

### Requirement: Export restrito ao dono

O sistema SHALL permitir o export apenas ao papel `owner`, porque o arquivo contém
e-mails de membros e convites (D-EXP-ROLE, §4.1).

#### Scenario: membro edit é negado
- **WHEN** um usuário com papel `edit` envia `POST /api/v1/workspace/backups`
- **THEN** a resposta é `403`
- **AND** nenhuma linha é criada em `workspace_backups`

#### Scenario: membro view é negado
- **WHEN** um usuário com papel `view` envia `POST /api/v1/workspace/backups`
- **THEN** a resposta é `403`
- **AND** nenhum arquivo é gerado

### Requirement: Round-trip com o importador legado

O sistema SHALL manter o formato do backup como contrato compartilhado com
`legacy-data-migration`, provado por um fixture versionado e por um teste de ida e volta
que preserva os identificadores (D-EXP, D1).

#### Scenario: exportar, importar e exportar de novo produz o mesmo payload
- **WHEN** um workspace com 3 projetos, 8 células, 24 robôs e 500 tarefas é exportado,
  importado num workspace vazio e exportado novamente
- **THEN** os dois payloads são iguais byte a byte, desconsiderando `_rt.exportedAt` e
  `_rt.checksum`
- **AND** todos os uuid de projetos, células, robôs e tarefas são os mesmos

#### Scenario: arquivo sem `_rt` é tratado como formato 1
- **WHEN** o importador recebe um arquivo `RoboTrack_Database.json` sem a chave `_rt`
- **THEN** ele o interpreta com o parser da versão `1` (legado)
- **AND** ignora ausência de `assigneeIds` e `advances`, usando `assignees` e `history`

### Requirement: Export grande não bloqueia a requisição

O sistema SHALL executar o export de forma síncrona apenas até o teto de 5.000 tarefas e,
acima dele, SHALL enfileirar um job Sidekiq que produz o arquivo e disponibiliza um link
de download, mantendo o mesmo formato e o mesmo nome de arquivo.

#### Scenario: workspace acima do teto vira job
- **WHEN** um `owner` exporta um workspace com 12.000 tarefas
- **THEN** a resposta é `202` com o `backup_id` e `status = "pending"`
- **AND** ao término do job o `status` vira `completed` e o link de download entrega
  `RoboTrack_Database.json`

#### Scenario: job falho não deixa backup utilizável
- **WHEN** o job de export falha na metade
- **THEN** a linha em `workspace_backups` fica com `status = "failed"`
- **AND** esse `backup_id` não satisfaz a pré-condição de backup do reset de fábrica
