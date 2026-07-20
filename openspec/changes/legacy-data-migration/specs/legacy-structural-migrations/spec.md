## ADDED Requirements

### Requirement: Pré-processador offline substitui a migração automática de runtime (§4.4)

As duas migrações estruturais de §4.4 SHALL ser executadas por uma tarefa offline
`rake legacy:normalize[entrada,saida]` que transforma o export bruto em um export
canônico, e MUST NOT ser implementadas como código de runtime disparado por leitura. A
substituição de mecanismo SHALL ser declarada no relatório da tarefa.

#### Scenario: projetos aninhados no documento do workspace viram registros próprios

- **WHEN** o export bruto contém `workspace.projects` como um array de 3 projetos dentro
  do documento do workspace
- **THEN** o arquivo canônico contém uma coleção `projects` de topo com 3 entradas, cada
  uma carregando `workspaceId`, e o documento do workspace no canônico **não** contém a
  chave `projects`

#### Scenario: logs aninhados viram coleção própria

- **WHEN** o export bruto contém `workspace.logs` com 120 entradas
- **THEN** o arquivo canônico contém uma coleção `logs` de topo com 120 entradas, cada uma
  com `workspaceId`, e o documento do workspace **não** contém a chave `logs`

#### Scenario: export já no formato novo passa intacto

- **WHEN** o export bruto já tem `projects` e `logs` como coleções de topo e não tem as
  chaves aninhadas
- **THEN** as duas migrações não são aplicadas e o relatório reporta
  `migracoes_aplicadas: 0`

### Requirement: Execução única preservada pelo artefato canônico

Rodar `legacy:normalize` sobre um arquivo que já é canônico (`schemaVersion: 1` presente)
SHALL ser um no-op idempotente. A tarefa MUST NOT aplicar as migrações estruturais duas
vezes sobre o mesmo conteúdo.

#### Scenario: normalize duas vezes produz arquivos byte a byte idênticos

- **WHEN** `rake legacy:normalize[bruto.json,a.json]` roda e em seguida
  `rake legacy:normalize[a.json,b.json]`
- **THEN** o SHA-256 de `a.json` e de `b.json` é idêntico e o segundo run reporta
  `entrada_ja_canonica: true`

#### Scenario: arquivo canônico declara schemaVersion

- **WHEN** `legacy:normalize` conclui com sucesso
- **THEN** a primeira chave do documento de saída é `"schemaVersion": 1`

### Requirement: Autoria do dono preservada como procedência do arquivo

A propriedade legada "só pelo dono" SHALL ser preservada registrando `ownerUid` do
workspace no arquivo canônico e em `legacy_import_runs.legacy_owner_uid`, e recusando o
import quando o dono do workspace de destino não corresponder.

#### Scenario: ownerUid ausente no export bruto bloqueia a normalização

- **WHEN** o export bruto não contém `ownerUid` no documento do workspace
- **THEN** `legacy:normalize` falha sem escrever o arquivo de saída, com mensagem citando
  `ownerUid ausente — procedência do export não verificável`

#### Scenario: ownerUid é propagado para o canônico

- **WHEN** o export bruto tem `ownerUid: "u-123"`
- **THEN** o arquivo canônico contém `workspace.ownerUid == "u-123"` e o import grava esse
  valor em `legacy_import_runs.legacy_owner_uid`

### Requirement: Atomicidade da transformação

`legacy:normalize` SHALL ser uma transformação pura arquivo→arquivo: ou o arquivo de saída
é escrito completo e válido, ou nenhum arquivo de saída é deixado em disco. Os campos
antigos migrados MUST NOT ser copiados para o canônico.

#### Scenario: falha no meio da transformação não deixa arquivo parcial

- **WHEN** a normalização aborta ao encontrar uma entrada de `logs` sem `ts` no projeto 2
  de 3
- **THEN** o caminho de saída não existe em disco (nem vazio, nem parcial) e o código de
  saída da rake é diferente de zero

#### Scenario: campos antigos são removidos, não duplicados

- **WHEN** o canônico é gerado a partir de um bruto com `workspace.projects` e
  `workspace.logs`
- **THEN** uma busca por `"projects"` e `"logs"` dentro do objeto `workspace` do canônico
  não encontra nenhuma ocorrência, e as coleções de topo contêm exatamente a mesma
  contagem de itens que os arrays aninhados tinham

### Requirement: Validação de schema antes do import

O export canônico SHALL ser validado contra `config/legacy_export_v1.schema.json` antes de
qualquer escrita no banco. Uma violação SHALL falhar o run apontando o caminho JSON do
campo ofensor.

#### Scenario: arquivo canônico inválido falha antes da primeira escrita

- **WHEN** o canônico tem um robô com `application: 42` (número em vez de string) no
  caminho `projects[1].cells[0].robots[3]`
- **THEN** o import falha citando esse caminho exato, e `SELECT count(*) FROM projects`
  permanece inalterado

#### Scenario: export bruto não é validado pelo schema v1

- **WHEN** `legacy:normalize` recebe um export bruto com projetos aninhados (que por
  definição viola o schema v1)
- **THEN** a normalização prossegue normalmente, porque a validação de schema se aplica
  apenas ao canônico
