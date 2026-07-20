# audit-log

## ADDED Requirements

### Requirement: Esquema e tenancy do log de auditoria

O sistema SHALL persistir cada registro de auditoria numa tabela `audit_logs` com PK
composta `(ts, id)` onde `id` é `uuid` gerável no cliente (D1/D13), e com as colunas
`workspace_id uuid NOT NULL`, `msg text NOT NULL`, `ts timestamptz NOT NULL DEFAULT now()`
(relógio do servidor), `ts_local text NOT NULL`, `by_person_id uuid NULL`,
`by_name text NOT NULL`, `event_type text NOT NULL`, `format_version integer NOT NULL` e
`payload jsonb NOT NULL DEFAULT '{}'` (§1.1 — entidade Log de auditoria).

`audit_logs` SHALL ter Row Level Security habilitada com política de `SELECT` e `INSERT`
restrita a `workspace_id = current_setting('app.current_workspace_id')::uuid` (D2), e
SHALL NOT declarar política de `UPDATE` ou `DELETE`.

`audit_logs` SHALL NOT ter chave estrangeira para `projects`, `cells`, `robots` ou
`tasks`; identificadores dessas entidades SHALL viver em `payload`. A FK para `workspaces`
SHALL ser `ON DELETE RESTRICT`.

#### Scenario: Registro exige workspace
- **WHEN** um `INSERT` em `audit_logs` omite `workspace_id`
- **THEN** o banco SHALL rejeitar com violação de `NOT NULL` e nenhuma linha SHALL ser
  gravada

#### Scenario: Leitura não enxerga registro de outro tenant
- **GIVEN** o workspace `A` com 3 registros e o workspace `B` com 5 registros
- **WHEN** uma sessão com `app.current_workspace_id` = id de `A` executa
  `SELECT count(*) FROM audit_logs`
- **THEN** o resultado SHALL ser `3`

#### Scenario: Escrita cruzada de tenant é barrada pela RLS
- **GIVEN** uma sessão com `app.current_workspace_id` = id do workspace `A`
- **WHEN** ela tenta `INSERT` de um registro com `workspace_id` = id do workspace `B`
- **THEN** o banco SHALL rejeitar por violação da política `WITH CHECK` da RLS

#### Scenario: Referência a robô sobrevive à remoção do robô
- **GIVEN** um registro cujo `payload` contém `robot_id` e `robot_name: "R-014"`
- **WHEN** o robô `R-014` é excluído da hierarquia
- **THEN** o registro SHALL continuar existindo com `payload.robot_name = "R-014"`

### Requirement: Imutabilidade garantida por privilégio revogado

A migração SHALL executar `REVOKE UPDATE, DELETE ON audit_logs FROM` o papel Postgres de
runtime da aplicação, e a aplicação SHALL conectar-se com esse papel em todos os
ambientes. O papel de runtime SHALL possuir apenas `SELECT` e `INSERT` em `audit_logs`
(§4.1 inv. 3).

O processo da aplicação SHALL verificar no boot que
`has_table_privilege(current_user, 'audit_logs', 'UPDATE')` é falso e SHALL recusar-se a
iniciar caso seja verdadeiro.

#### Scenario: UPDATE direto pelo console de produção falha
- **GIVEN** um registro de auditoria com `msg = 'Em [R-014], Ana concluiu a tarefa "Solda
  ponto 3" com 100%.'`
- **WHEN** o operador executa no `rails console` de produção
  `ActiveRecord::Base.connection.execute("UPDATE audit_logs SET msg = 'x'")`
- **THEN** o Postgres SHALL levantar `insufficient_privilege` (SQLSTATE 42501)
- **AND** o `msg` do registro SHALL permanecer inalterado

#### Scenario: delete_all pelo model falha no banco, não no model
- **WHEN** o operador executa `AuditLog.delete_all` no console
- **THEN** a operação SHALL falhar com erro do Postgres de privilégio insuficiente
- **AND** a contagem de registros SHALL permanecer a mesma

#### Scenario: Aplicação recusa subir com papel privilegiado demais
- **GIVEN** um `DATABASE_URL` apontando para o papel dono das tabelas
- **WHEN** o processo Rails inicializa
- **THEN** ele SHALL abortar o boot com mensagem nomeando `audit_logs` e o privilégio
  `UPDATE` indevido

### Requirement: Imutabilidade garantida por trigger, inclusive para o papel dono

O sistema SHALL instalar a função `audit_logs_immutable()` e a trigger
`BEFORE UPDATE OR DELETE ON audit_logs FOR EACH ROW`, que SHALL levantar exceção
incondicionalmente, sem consultar papel, sessão ou conteúdo da linha (§2.8, §4.1 inv. 3).

#### Scenario: Papel dono da tabela também é barrado no UPDATE
- **GIVEN** uma sessão conectada com o papel `robotrack_migrator`, dono de `audit_logs`,
  para o qual o `REVOKE` não tem efeito
- **WHEN** executa `UPDATE audit_logs SET by_name = 'outro' WHERE id = '<uuid>'`
- **THEN** a trigger SHALL levantar exceção e a transação SHALL abortar

#### Scenario: Papel dono também é barrado no DELETE
- **GIVEN** a mesma sessão do papel `robotrack_migrator`
- **WHEN** executa `DELETE FROM audit_logs WHERE id = '<uuid>'`
- **THEN** a trigger SHALL levantar exceção e nenhuma linha SHALL ser removida

#### Scenario: O dono do workspace não é exceção
- **GIVEN** um usuário autenticado que é `owner` do workspace
- **WHEN** ele emite qualquer requisição que tente alterar ou remover um registro de
  auditoria do seu próprio workspace
- **THEN** o sistema SHALL negar
- **AND** a negação SHALL vir do banco (privilégio ou trigger), não de validação de model

#### Scenario: INSERT continua permitido
- **WHEN** o papel de runtime executa um `INSERT` válido em `audit_logs`
- **THEN** a linha SHALL ser gravada e a trigger SHALL NOT disparar

### Requirement: Ausência de superfície de mutação na API

A API SHALL expor exatamente um endpoint para auditoria,
`GET /api/v1/workspaces/:workspace_id/audit_logs`, e SHALL NOT expor rota `POST`, `PUT`,
`PATCH` ou `DELETE` para `audit_logs` (§4.1 inv. 1 — autorização no servidor).

Registros SHALL ser produzidos exclusivamente por `AuditLog::RecordService`, chamado por
código de servidor.

#### Scenario: Rota de escrita não existe
- **WHEN** um cliente autenticado envia
  `POST /api/v1/workspaces/<id>/audit_logs` com corpo válido
- **THEN** a API SHALL responder `404`

#### Scenario: Rota de exclusão não existe
- **WHEN** um cliente autenticado com papel `owner` envia
  `DELETE /api/v1/workspaces/<id>/audit_logs/<log_id>`
- **THEN** a API SHALL responder `404`

#### Scenario: Route-sweep enxerga uma única rota declarando policy
- **WHEN** o spec de varredura de rotas (D3) enumera os endpoints de auditoria
- **THEN** SHALL encontrar exatamente 1 endpoint
- **AND** ele SHALL declarar `AuditLogPolicy`

### Requirement: Registro automático de conclusão de tarefa a 100%

Quando um avanço leva o progresso de uma tarefa a `100` e o status resultante é
`Concluído`, o sistema SHALL gravar um registro de auditoria com
`event_type = 'task_completed'` **na mesma transação de banco** do avanço (§2.2, §2.8).

Se a gravação do registro falhar, a transação inteira SHALL sofrer rollback e o avanço
SHALL NOT ser persistido.

#### Scenario: Conclusão gera exatamente um registro
- **GIVEN** a tarefa `"Solda ponto 3"` do robô `R-014` com progresso `45`
- **WHEN** a pessoa `Ana Ribeiro` registra um avanço de `45` para `100`
- **THEN** SHALL existir 1 registro novo com `event_type = 'task_completed'`,
  `by_name = 'Ana Ribeiro'` e `by_person_id` igual ao `person_id` de Ana

#### Scenario: Avanço que não chega a 100 não gera registro
- **GIVEN** a tarefa `"Solda ponto 3"` com progresso `45`
- **WHEN** a pessoa registra um avanço de `45` para `90`
- **THEN** a contagem de registros de auditoria do workspace SHALL permanecer inalterada

#### Scenario: Falha na gravação do log derruba o avanço
- **GIVEN** um erro forçado no `INSERT` de `audit_logs`
- **WHEN** um avanço de `90` para `100` é submetido
- **THEN** a resposta SHALL ser erro
- **AND** o progresso da tarefa SHALL permanecer `90`
- **AND** nenhum `task_advance` novo SHALL existir

#### Scenario: Retentativa da fila offline não duplica o registro
- **GIVEN** um avanço de `90` para `100` com `id` uuid `a1b2…` gerado no cliente, já
  aplicado no servidor
- **WHEN** a fila offline reenvia a mesma mutação com o mesmo `id`
- **THEN** o número de registros com `event_type = 'task_completed'` para essa tarefa
  SHALL permanecer `1`

### Requirement: Mensagem produzida por format string versionada em locale

O texto do registro SHALL ser produzido a partir de uma chave de locale versionada em
`config/locales/pt-BR.audit.yml` (D14), com `format_version` gravado na linha, e SHALL NOT
ser montado por interpolação literal em código Ruby.

Uma versão de format string já referenciada por registros existentes SHALL NOT ser
editada; alterações de texto SHALL criar uma nova versão.

#### Scenario: Texto renderizado corresponde ao formato do legado
- **GIVEN** o robô `R-014`, a tarefa `"Solda ponto 3"` e a responsável `Ana Ribeiro`
- **WHEN** a tarefa é concluída a 100%
- **THEN** `msg` SHALL ser exatamente
  `Em [R-014], Ana Ribeiro concluiu a tarefa "Solda ponto 3" com 100%.`

#### Scenario: Múltiplos responsáveis são unidos no snapshot
- **GIVEN** a tarefa `"Comissionamento de garra"` do robô `R-002` com responsáveis
  `Ana Ribeiro` e `Bruno Sá`
- **WHEN** a tarefa é concluída a 100%
- **THEN** `msg` SHALL conter `Ana Ribeiro, Bruno Sá` na posição dos responsáveis
- **AND** o verbo SHALL permanecer `concluiu`, fiel ao formato `v1`

#### Scenario: Tarefa sem responsável usa a pessoa auto-atribuída
- **GIVEN** a tarefa `"Backup de programa"` sem nenhum responsável (D11: conjunto vazio)
- **WHEN** `Bruno Sá` a leva a 100% e a auto-atribuição de §2.3 o registra como responsável
- **THEN** `msg` SHALL nomear `Bruno Sá` na posição dos responsáveis

#### Scenario: CI bloqueia edição de versão publicada
- **GIVEN** a chave `audit.task_completed.v1` presente na branch `main`
- **WHEN** um commit altera o texto dessa chave em vez de criar `v2`
- **THEN** o spec de verificação de format strings SHALL falhar nomeando a chave alterada

### Requirement: Texto exibido é congelado na escrita

O sistema SHALL materializar `msg` e `ts_local` no momento do `INSERT` e SHALL exibir
`msg` verbatim, sem re-renderizar a partir de `payload` ou do arquivo de locale (§1.1 —
`tsLocal` é texto formatado).

#### Scenario: Edição posterior do locale não altera registro histórico
- **GIVEN** um registro gravado com `format_version = 1` e
  `msg = 'Em [R-014], Ana Ribeiro concluiu a tarefa "Solda ponto 3" com 100%.'`
- **WHEN** uma `v2` da format string é publicada com texto diferente
- **THEN** o registro existente SHALL continuar exibindo o texto original

#### Scenario: ts_local é formatado no servidor
- **GIVEN** um registro criado com `ts = 2026-03-14T18:07:00Z`
- **WHEN** o registro é lido por um cliente cujo navegador está em `UTC`
- **THEN** `ts_local` SHALL ser o texto formatado no fuso do servidor
  (`America/Sao_Paulo`), idêntico ao lido por um cliente em qualquer outro fuso

### Requirement: Autoria por identidade estável com snapshot de nome

O sistema SHALL gravar `by_person_id` referenciando `people.id` (D10) e `by_name` como
snapshot imutável do nome no momento do registro. `by_person_id` SHALL ser nullable com
`ON DELETE SET NULL`; `by_name` SHALL ser `NOT NULL`.

#### Scenario: Renomear a pessoa não reescreve a trilha
- **GIVEN** um registro com `by_name = 'Ana Ribeiro'`
- **WHEN** a `Person` correspondente é renomeada para `Ana R. Souza`
- **THEN** o registro SHALL continuar exibindo `Ana Ribeiro`

#### Scenario: Remover a pessoa não apaga nem corrompe o registro
- **GIVEN** um registro com `by_person_id` preenchido e `by_name = 'Bruno Sá'`
- **WHEN** a `Person` de Bruno é removida
- **THEN** o registro SHALL continuar existindo com `by_person_id IS NULL` e
  `by_name = 'Bruno Sá'`

#### Scenario: Registro importado sem pessoa resolvível é aceito
- **GIVEN** um registro do export legado cujo `byName` é `"(nota anterior)"` e sem autor
  resolvível (§1.4)
- **WHEN** o importador o grava
- **THEN** o `INSERT` SHALL ser aceito com `by_person_id IS NULL` e
  `by_name = '(nota anterior)'`

### Requirement: Leitura limitada a 200 registros mais recentes

O endpoint de leitura SHALL retornar registros do workspace corrente ordenados por `ts`
decrescente e SHALL limitar a resposta a no máximo **200** registros, aplicando o teto no
servidor independentemente do parâmetro enviado pelo cliente (§2.8).

Todos os papéis do workspace (`owner`, `edit`, `view`) SHALL poder ler (§4.1 — "Ler tudo
do workspace").

#### Scenario: Modal com 250 registros exibe 200
- **GIVEN** um workspace com 250 registros de auditoria
- **WHEN** o usuário abre o modal de auditoria
- **THEN** a resposta SHALL conter exatamente 200 registros
- **AND** o primeiro SHALL ser o de `ts` mais recente
- **AND** o 200º SHALL ser o 200º mais recente, sem os 50 mais antigos

#### Scenario: Cliente não consegue exceder o teto
- **WHEN** o cliente requisita `?limit=1000` num workspace com 250 registros
- **THEN** a resposta SHALL conter 200 registros

#### Scenario: Membro view lê a auditoria
- **GIVEN** um membro com papel `view`
- **WHEN** ele abre o modal de auditoria
- **THEN** a resposta SHALL ser `200 OK` com os registros do workspace

#### Scenario: Não-membro é negado
- **GIVEN** um usuário autenticado que não é membro do workspace `A`
- **WHEN** ele requisita `GET /api/v1/workspaces/<A>/audit_logs`
- **THEN** a API SHALL responder `403` e o corpo SHALL NOT conter registro algum

### Requirement: O log sobrevive ao reset de fábrica e registra o evento

O reset de fábrica (§3.11, D12) SHALL NOT remover, alterar ou truncar registros de
`audit_logs`, e SHALL gravar um registro `event_type = 'workspace_reset'` dentro da mesma
transação em que remove projetos, células, robôs e tarefas.

O sistema SHALL expor a `workspace-settings` o contrato
`AuditLog::RecordService.record!(workspace:, event:, by:, payload:)` para esse fim. Se a
gravação falhar, o reset SHALL sofrer rollback integral.

#### Scenario: Registros anteriores ao reset permanecem
- **GIVEN** um workspace com 12 registros de auditoria e 3 projetos
- **WHEN** o dono executa o reset de fábrica
- **THEN** os 12 registros anteriores SHALL continuar existindo, inalterados
- **AND** o total SHALL passar a ser 13
- **AND** o 13º SHALL ter `event_type = 'workspace_reset'`

#### Scenario: Reset que tenta apagar auditoria é impossível por construção
- **WHEN** o serviço de reset emite `DELETE FROM audit_logs WHERE workspace_id = <id>`
- **THEN** a operação SHALL falhar por privilégio revogado ou pela trigger
- **AND** a transação atômica do reset SHALL sofrer rollback integral, sem remover projeto
  algum

#### Scenario: Falha ao registrar o reset aborta o reset
- **GIVEN** um erro forçado no `INSERT` do registro `workspace_reset`
- **WHEN** o dono executa o reset de fábrica
- **THEN** a resposta SHALL ser erro
- **AND** os 3 projetos SHALL continuar existindo

#### Scenario: Remover o workspace com auditoria é bloqueado pela FK
- **WHEN** alguém tenta `DELETE FROM workspaces WHERE id = <id>` num workspace com
  registros de auditoria
- **THEN** o Postgres SHALL rejeitar por violação de FK `ON DELETE RESTRICT`
