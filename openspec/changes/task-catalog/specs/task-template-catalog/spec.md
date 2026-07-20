# task-template-catalog

## ADDED Requirements

### Requirement: Modelo de template de tarefa

O sistema SHALL persistir os templates de tarefa-base numa tabela `task_templates` com
`id` uuid gerável no cliente (D1/D13), `workspace_id` uuid `NOT NULL` protegido por RLS
(D2), `cat` (texto, categoria), `desc` (texto, descrição), `weight` (numérico, default
`1`) e `app_filters` (`text[]`, `NOT NULL DEFAULT '{}'`, onde array vazio significa "vale
para todas as Aplicações"), conforme §1.1.

#### Scenario: Template criado sem peso recebe peso 1

- **WHEN** um template é criado com `cat: "F. Interlocks"`, `desc: "PLC-ROB
  interlocks/Sinais"` e nenhum `weight` informado
- **THEN** o registro persistido tem `weight == 1`

#### Scenario: Template criado sem filtro tem array vazio, não NULL

- **WHEN** um template é criado sem informar `appFilters`
- **THEN** a coluna `app_filters` contém `{}` (array vazio de zero elementos)
- **AND** uma tentativa de `UPDATE task_templates SET app_filters = NULL` direto no banco
  falha com violação de `NOT NULL`

#### Scenario: Cliente fornece o uuid do template

- **WHEN** o cliente envia `POST /api/v1/task_templates` com
  `id: "6f1a2b3c-0000-4000-8000-000000000001"`
- **THEN** o template é persistido com exatamente esse `id`
- **AND** um segundo `POST` com o mesmo `id` no mesmo workspace falha com `409`, sem criar
  segunda linha

### Requirement: Enum fechado de Aplicações

O sistema SHALL definir as Aplicações de §1.2 como um tipo enumerado do banco
(`robot_application`) contendo exatamente os seis valores `Misto / Geral`, `Solda Ponto`,
`Solda MIG`, `Handling`, `Sealing` e `Outros`, e SHALL expor essa lista ao cliente por um
endpoint de metadados, de modo que não exista uma segunda declaração da lista no frontend.

#### Scenario: Endpoint de metadados devolve os seis valores na ordem do enum

- **WHEN** o cliente faz `GET /api/v1/meta/robot_applications`
- **THEN** a resposta é exatamente
  `["Misto / Geral", "Solda Ponto", "Solda MIG", "Handling", "Sealing", "Outros"]`

#### Scenario: Valor fora do enum é rejeitado pelo banco

- **WHEN** um `INSERT` direto no banco tenta gravar
  `app_filters = '{"solda ponto"}'` (minúsculo, fora do enum)
- **THEN** o comando falha com violação do CHECK de `task_templates`
- **AND** nenhuma linha é criada

#### Scenario: A sentinela "Todas" é armazenável mas não pertence ao enum

- **WHEN** um `INSERT` direto no banco grava `app_filters = '{"Todas"}'`
- **THEN** o comando é aceito (o CHECK admite os seis valores do enum mais `"Todas"`)
- **AND** `GET /api/v1/meta/robot_applications` continua devolvendo seis valores, sem
  `"Todas"`

### Requirement: Seed do catálogo padrão em todo workspace novo

O sistema SHALL semear, na criação de todo workspace, os 31 templates de §1.3 distribuídos
em 9 categorias, todos com `weight: 1`, com filtro de aplicação vazio exceto por
`Calibração de Cola` (`["Sealing"]`) e `Check sinais de Gripper` (`["Handling",
"Solda Ponto"]`). O seed SHALL ocorrer na mesma transação da criação do workspace.

#### Scenario: Workspace novo nasce com 31 templates em 9 categorias

- **WHEN** um workspace é criado pelo bootstrap do primeiro login
- **THEN** `SELECT count(*) FROM task_templates WHERE workspace_id = <novo>` retorna `31`
- **AND** `SELECT count(DISTINCT cat)` retorna `9`
- **AND** todos os 31 têm `weight == 1`

#### Scenario: As categorias contêm exatamente as descrições de §1.3

- **WHEN** o catálogo do workspace novo é lido agrupado por `cat`
- **THEN** `A. Hardware` contém `Power On`, `Mastering Check`, `Montagem de Ferramenta`,
  `Check de Ferramenta/Umbilical`
- **AND** `B. Rede` contém `Config. Endereço de IP`, `Rede Principal`, `Sub Rede`
- **AND** `C. Segurança` contém `Definir Cubos e esferas de segurança`, `Self Check de
  segurança do Robo`
- **AND** `D. Processo` contém `TCP Check`, `Calibração de Frame`, `Payload`, `Calibração
  de Cola`, `Check sinais de Gripper`
- **AND** `E. Trajetórias` contém `Carregar OLP`, `Teach Traj. Sem Peça`, `Teach Traj. Com
  Peça`, `Carregar Parâmetros`, `Traj, de Descarte`, `Manutenção`
- **AND** `F. Interlocks` contém `PLC-ROB interlocks/Sinais`
- **AND** `G. Tryout` contém `Dryrun Baixa velocidade ate 100%`, `Dryrun Diferentes
  velocidades`, `Automatico baixa velocidade`, `Speed up`
- **AND** `H. Otimização` contém `Medição de Tempo de Ciclo Com peça`, `Otimização de
  Trajetoria`
- **AND** `I. Aceitação` contém `Check de aceitação interna`, `Check de aceitação do
  cliente`, `Treinamento ao cliente`, `Acompanhamento`

#### Scenario: Exatamente três templates do seed têm filtro de aplicação

- **WHEN** o catálogo semeado é consultado por `app_filters <> '{}'`
- **THEN** exatamente 1 linha é retornada com `desc == "Calibração de Cola"` e
  `app_filters == {"Sealing"}`
- **AND** exatamente 1 linha é retornada com `desc == "Check sinais de Gripper"` e
  `app_filters == {"Handling","Solda Ponto"}`
- **AND** o total de linhas com `app_filters <> '{}'` é `2`, ou seja, os outros 29
  templates têm filtro vazio

#### Scenario: Falha no seed aborta a criação do workspace

- **WHEN** o `insert_all` dos 31 templates falha (ex.: violação de CHECK injetada no teste)
- **THEN** a transação de bootstrap é revertida
- **AND** nenhum workspace é criado — não existe workspace com zero templates

#### Scenario: Catálogos de workspaces diferentes são independentes

- **WHEN** o workspace A exclui `Speed up` do seu catálogo
- **THEN** o catálogo do workspace B continua com `Speed up` e mantém 31 templates
- **AND** o catálogo do workspace A passa a ter 30

### Requirement: Ordenação lexicográfica de categorias pelo prefixo

O sistema SHALL manter o prefixo alfabético (`A.`, `B.`, …) dentro da string `cat` e SHALL
ordenar o catálogo por `cat` com collation binária explícita (`COLLATE "C"`), sem campo de
ordem separado, conforme a nota de §1.3.

#### Scenario: A listagem devolve as 9 categorias na ordem A a I

- **WHEN** o cliente faz `GET /api/v1/task_templates` num workspace recém-semeado
- **THEN** a sequência de `cat` distintos na resposta é, nesta ordem exata:
  `A. Hardware`, `B. Rede`, `C. Segurança`, `D. Processo`, `E. Trajetórias`,
  `F. Interlocks`, `G. Tryout`, `H. Otimização`, `I. Aceitação`

#### Scenario: Categoria criada sem prefixo é aceita e ordena de forma determinística

- **WHEN** um editor cria um template com `cat: "Comissionamento Elétrico"` (sem prefixo)
- **THEN** a criação é aceita, sem erro de validação
- **AND** na listagem essa categoria aparece depois de `I. Aceitação`, e a mesma ordem é
  produzida em ambiente com locale `pt_BR.UTF-8` e com locale `C`

### Requirement: Regra de aplicabilidade de template a um robô

O sistema SHALL considerar que um template se aplica a um robô se, e somente se, seu
`app_filters` está vazio **OU** contém `"Misto / Geral"` **OU** contém `"Todas"` **OU**
contém a Aplicação do robô (§2.5). Essa regra SHALL residir num único componente,
consumido tanto pela criação de robôs em lote quanto pela sincronização retroativa.

#### Scenario: Robô Solda MIG não recebe Calibração de Cola

- **WHEN** a aplicabilidade do catálogo padrão é avaliada para um robô com
  `application: "Solda MIG"`
- **THEN** o conjunto aplicável tem 29 templates
- **AND** não contém `Calibração de Cola` nem `Check sinais de Gripper`

#### Scenario: Robô Handling recebe Check sinais de Gripper mas não Calibração de Cola

- **WHEN** a aplicabilidade do catálogo padrão é avaliada para um robô com
  `application: "Handling"`
- **THEN** o conjunto aplicável tem 30 templates
- **AND** contém `Check sinais de Gripper`
- **AND** não contém `Calibração de Cola`

#### Scenario: Robô Sealing recebe Calibração de Cola

- **WHEN** a aplicabilidade do catálogo padrão é avaliada para um robô com
  `application: "Sealing"`
- **THEN** o conjunto aplicável tem 30 templates
- **AND** contém `Calibração de Cola`
- **AND** não contém `Check sinais de Gripper`

#### Scenario: Robô Misto / Geral recebe apenas os 29 sem filtro

- **WHEN** a aplicabilidade do catálogo padrão é avaliada para um robô com
  `application: "Misto / Geral"`
- **THEN** o conjunto aplicável tem 29 templates
- **AND** não contém `Calibração de Cola` nem `Check sinais de Gripper`, porque o filtro
  desses dois não está vazio e não contém `"Misto / Geral"`

#### Scenario: A sentinela "Misto / Geral" no filtro faz o template valer para todos

- **WHEN** um template `desc: "Check de aterramento"` tem
  `app_filters == {"Misto / Geral","Sealing"}` gravado no banco
- **THEN** ele é aplicável a um robô `Solda Ponto`, a um robô `Outros` e a um robô
  `Handling`

#### Scenario: A sentinela legada "Todas" no filtro faz o template valer para todos

- **WHEN** um template `desc: "Check de aterramento"` tem `app_filters == {"Todas"}`
  gravado direto no banco (dado vindo da importação legada)
- **THEN** ele é aplicável a um robô `Solda MIG`
- **AND** é aplicável a um robô `Sealing`

#### Scenario: Os dois caminhos consumidores produzem o mesmo conjunto

- **WHEN** o mesmo catálogo e o mesmo robô `Handling` são avaliados pela criação em lote e
  pela sincronização retroativa
- **THEN** os dois caminhos retornam conjuntos de `desc` idênticos (30 itens), provando
  que compartilham o componente de aplicabilidade

### Requirement: Compatibilidade com o nome de campo legado `apps`

O sistema SHALL aceitar, no corpo das requisições de escrita de template, tanto
`appFilters` quanto o nome antigo `apps` (§1.4 item 3), e SHALL sempre responder com
`appFilters`.

#### Scenario: Escrita com o nome legado apps é aceita

- **WHEN** o cliente envia `POST /api/v1/task_templates` com
  `{"cat":"D. Processo","desc":"Check de cola","apps":["Sealing"]}`
- **THEN** o template é criado com `app_filters == {"Sealing"}`
- **AND** a resposta contém a chave `appFilters` e **não** contém a chave `apps`

#### Scenario: appFilters vence quando os dois nomes são enviados

- **WHEN** o cliente envia `{"apps":["Handling"],"appFilters":["Sealing"]}`
- **THEN** o template é criado com `app_filters == {"Sealing"}`
- **AND** um aviso estruturado é registrado no log indicando o envio duplicado

### Requirement: Criação, edição e exclusão de template

O sistema SHALL oferecer CRUD de template no escopo do workspace corrente (§3.9),
validando presença de `cat` e `desc` e `weight > 0`.

#### Scenario: Criação com categoria e descrição

- **WHEN** um editor envia `POST /api/v1/task_templates` com
  `{"cat":"J. Elétrica","desc":"Check de aterramento"}`
- **THEN** a resposta é `201` com `weight: 1` e `appFilters: []`

#### Scenario: Descrição vazia é rejeitada

- **WHEN** um editor envia `POST /api/v1/task_templates` com `{"cat":"A. Hardware",
  "desc":"   "}`
- **THEN** a resposta é `422` com erro em `desc`
- **AND** a contagem de templates do workspace permanece `31`

#### Scenario: Exclusão remove o template mas não afeta tarefas já criadas

- **WHEN** o template `Speed up` é excluído do catálogo de um workspace onde o robô
  `R01 - Solda` já tem a tarefa `Speed up` com progresso `40`
- **THEN** o catálogo passa a ter 30 templates
- **AND** a tarefa `Speed up` do robô `R01 - Solda` continua existindo com progresso `40`

#### Scenario: Editar um template não propaga para tarefas existentes

- **WHEN** o template `TCP Check` tem seu `weight` alterado de `1` para `3`
- **THEN** a tarefa `TCP Check` já materializada no robô `R01 - Solda` continua com
  `weight == 1`
- **AND** robôs criados a partir daí recebem `TCP Check` com `weight == 3`

### Requirement: Editar o filtro de aplicação, com `Misto / Geral` limpando o filtro

Ao editar o filtro de aplicação de um template (§3.9), o sistema SHALL normalizar antes de
persistir: se o valor recebido for vazio, ou contiver `"Misto / Geral"`, ou contiver
`"Todas"`, o filtro persistido SHALL ser um array vazio. Duplicatas SHALL ser removidas.

#### Scenario: Escolher Misto / Geral limpa o filtro

- **WHEN** o template `Calibração de Cola`, com `app_filters == {"Sealing"}`, é editado
  para `appFilters: ["Misto / Geral"]`
- **THEN** o registro persistido tem `app_filters == {}`
- **AND** o template passa a ser aplicável a um robô `Solda MIG`

#### Scenario: Enviar a sentinela Todas também limpa o filtro

- **WHEN** um template é editado para `appFilters: ["Todas"]` via API
- **THEN** o registro persistido tem `app_filters == {}` — a string `"Todas"` não é gravada
  por escrita de API

#### Scenario: Misto / Geral misturado com outra aplicação ainda limpa

- **WHEN** um template é editado para `appFilters: ["Handling", "Misto / Geral"]`
- **THEN** o registro persistido tem `app_filters == {}`, e não `{"Handling"}`

#### Scenario: Duplicatas são removidas preservando a ordem

- **WHEN** um template é editado para
  `appFilters: ["Handling","Solda Ponto","Handling"]`
- **THEN** o registro persistido tem `app_filters == {"Handling","Solda Ponto"}`

#### Scenario: Filtro com valor inválido é rejeitado

- **WHEN** um template é editado para `appFilters: ["Solda a Laser"]`
- **THEN** a resposta é `422`
- **AND** o `app_filters` anterior do template permanece inalterado no banco

### Requirement: Autorização e isolamento de tenant do catálogo

Toda leitura e escrita do catálogo SHALL declarar uma policy (D3). Membros `owner` e
`edit` SHALL poder criar, editar e excluir templates; membros `view` SHALL apenas ler
(§4.1). Templates SHALL ser invisíveis fora do workspace ao qual pertencem, por RLS (D2).

#### Scenario: Membro view lê o catálogo

- **WHEN** um membro com papel `view` faz `GET /api/v1/task_templates`
- **THEN** a resposta é `200` com os 31 templates do workspace

#### Scenario: Membro view não pode criar template

- **WHEN** um membro com papel `view` envia `POST /api/v1/task_templates` com
  `{"cat":"A. Hardware","desc":"Check extra"}`
- **THEN** a resposta é `403`
- **AND** a contagem de templates do workspace continua `31` — nenhuma linha foi escrita

#### Scenario: Membro view não pode editar nem excluir template

- **WHEN** um membro com papel `view` envia `PATCH /api/v1/task_templates/<id de TCP
  Check>` com `{"weight": 5}`
- **THEN** a resposta é `403`
- **AND** o `weight` de `TCP Check` permanece `1`
- **AND** um `DELETE` no mesmo id também responde `403` e o template continua existindo

#### Scenario: Template de outro workspace é invisível

- **WHEN** um usuário autenticado no workspace A faz
  `GET /api/v1/task_templates/<id de um template do workspace B>`
- **THEN** a resposta é `404` (e não `403`)
- **AND** a consulta ao banco retorna zero linhas, porque a RLS filtrou a linha antes do
  service

#### Scenario: Editor de um workspace não altera catálogo de outro

- **WHEN** um usuário com papel `edit` no workspace A envia `PATCH
  /api/v1/task_templates/<id de "Payload" do workspace B>` com `{"desc":"Hackeado"}`
- **THEN** a resposta é `404`
- **AND** o template `Payload` do workspace B mantém `desc == "Payload"`

#### Scenario: Endpoint sem policy declarada quebra o CI

- **WHEN** um endpoint de `task_templates` é adicionado sem declarar policy
- **THEN** o route-sweep spec de `authorization-policies` falha
