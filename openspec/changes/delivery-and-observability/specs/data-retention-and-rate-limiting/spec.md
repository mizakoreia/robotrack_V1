## ADDED Requirements

### Requirement: `audit_logs` particionada por mês

O sistema SHALL criar `audit_logs` como tabela particionada por RANGE em `recorded_at`,
com uma partição por mês, e SHALL manter no mínimo duas partições futuras pré-criadas.

#### Scenario: insert cai na partição do mês

- **WHEN** um registro de auditoria com `recorded_at = 2026-08-14T10:00:00Z` é inserido
- **THEN** a linha SHALL residir na partição `audit_logs_2026_08`

#### Scenario: partição futura é pré-criada com folga

- **WHEN** o job de manutenção de partições roda em 2026-08-01
- **THEN** as partições de 2026-09 e 2026-10 SHALL existir

#### Scenario: folga insuficiente gera alerta

- **WHEN** existe apenas uma partição futura no momento da verificação
- **THEN** um alerta `warning` com `key: "audit_partition_runway"` SHALL ser levantado via
  `Ops::AlertService`
- **AND** o job SHALL criar as partições faltantes na mesma execução

#### Scenario: ausência de partição não pode derrubar escrita de auditoria

- **WHEN** um insert é tentado para `recorded_at` fora de toda partição existente
- **THEN** o job de manutenção SHALL ter criado a partição antes, e a verificação
  automatizada SHALL falhar o build se a folga configurada for menor que 2

### Requirement: Retenção de auditoria sem violar o REVOKE de D12

O sistema SHALL expurgar auditoria antiga exclusivamente por `DETACH PARTITION` seguido de
`DROP TABLE` da partição, e o papel de runtime da aplicação SHALL permanecer sem
privilégio de `UPDATE` e `DELETE` sobre `audit_logs`.

#### Scenario: partição expirada é descartada após exportação

- **WHEN** a retenção é de 24 meses e a partição `audit_logs_2024_05` está fora da janela
- **THEN** o job SHALL exportar seu conteúdo para armazenamento de objeto
- **AND** SHALL executar `ALTER TABLE audit_logs DETACH PARTITION audit_logs_2024_05`
  seguido de `DROP TABLE audit_logs_2024_05`
- **AND** SHALL registrar a operação no log estruturado com a contagem de linhas exportada

#### Scenario: drop antes da exportação é proibido

- **WHEN** a exportação da partição falha
- **THEN** o `DROP TABLE` SHALL NOT ser executado
- **AND** um alerta `warning` SHALL ser levantado

#### Scenario: privilégio de DELETE permanece revogado

- **WHEN** o papel de runtime executa `DELETE FROM audit_logs WHERE id = '…'`
- **THEN** o Postgres SHALL recusar com erro de permissão
- **AND** a existência do job de retenção SHALL NOT ter concedido `DELETE` a nenhum papel

#### Scenario: privilégio de UPDATE permanece revogado

- **WHEN** o papel de runtime executa `UPDATE audit_logs SET message = 'x'`
- **THEN** o Postgres SHALL recusar com erro de permissão

### Requirement: Retenção de notificações

O sistema SHALL expurgar registros de `notifications` mais antigos que `NOTIFICATIONS_
RETENTION_DAYS` (padrão 90), em lotes, sem lock prolongado.

#### Scenario: notificação antiga lida é removida

- **WHEN** existe uma notificação com `created_at` de 120 dias atrás e `read = true`
- **THEN** o job de retenção SHALL removê-la

#### Scenario: notificação recente não lida é preservada

- **WHEN** existe uma notificação com `created_at` de 30 dias atrás e `read = false`
- **THEN** ela SHALL permanecer

#### Scenario: expurgo é feito em lotes

- **WHEN** 500.000 notificações estão elegíveis
- **THEN** o job SHALL removê-las em lotes de no máximo 5.000 por transação
- **AND** nenhuma transação individual SHALL exceder 30 segundos

### Requirement: Retenção de códigos e tentativas de autenticação

O sistema SHALL remover registros expirados de `login_codes`, `login_attempts` e entradas
de `jwt_denylist` cujo `exp` já passou.

#### Scenario: código de login expirado é removido

- **WHEN** existe um `login_code` com expiração há 3 dias
- **THEN** o job de retenção SHALL removê-lo

#### Scenario: entrada de denylist além da expiração do token é removida

- **WHEN** uma entrada de `jwt_denylist` tem `exp` de 8 dias atrás e o TTL máximo de
  refresh é 7 dias
- **THEN** a entrada SHALL ser removida
- **AND** um token com esse `jti` SHALL continuar sendo rejeitado por estar expirado, não
  por estar na denylist

#### Scenario: retenção não apaga denylist ativa

- **WHEN** uma entrada de denylist tem `exp` daqui a 2 dias
- **THEN** ela SHALL permanecer, para que o logout continue efetivo

### Requirement: Execução agendada e observável dos jobs de retenção

O sistema SHALL agendar os jobs de retenção diariamente, e cada execução SHALL registrar
tabela, linhas afetadas e duração; falha SHALL levantar alerta.

#### Scenario: execução bem-sucedida é registrada

- **WHEN** o job de retenção de notificações remove 4.310 linhas em 12 segundos
- **THEN** uma linha de log estruturado SHALL conter `table=notifications`, `rows=4310` e
  `duration_ms`

#### Scenario: falha do job alerta

- **WHEN** o job de retenção falha por timeout
- **THEN** um alerta `warning` com `key: "retention_job_failure:<tabela>"` SHALL ser
  levantado

#### Scenario: job não roda concorrentemente consigo mesmo

- **WHEN** uma execução do job de retenção ainda está em andamento e o agendamento dispara
  a próxima
- **THEN** a segunda execução SHALL ser descartada
- **AND** SHALL registrar a razão no log

### Requirement: Contador de rate limit compartilhado entre processos

O sistema SHALL configurar o store do `rack-attack` no Redis de cache, de forma que o
contador seja global ao ambiente e não por processo Puma.

#### Scenario: limite não é multiplicado pelo número de processos

- **WHEN** o limite é 120 requisições por minuto e a aplicação roda com 4 processos Puma
- **THEN** a 121ª requisição do mesmo usuário no minuto SHALL responder 429,
  independentemente de qual processo a atendeu
- **AND** o store SHALL NOT ser `ActiveSupport::Cache::MemoryStore`

### Requirement: Rate limit por identidade autenticada, com IP como fallback

O sistema SHALL chavear o throttle por `user_id` quando houver JWT válido e por IP apenas
quando não houver, e SHALL derivar o IP do cabeçalho de proxy confiável.

#### Scenario: usuários atrás do mesmo NAT não se bloqueiam

- **WHEN** 8 engenheiros da mesma fábrica compartilham o IP público `200.1.2.3` e um deles
  excede seu limite de escrita
- **THEN** apenas as requisições daquele `user_id` SHALL receber 429
- **AND** os outros 7 SHALL continuar recebendo 2xx

#### Scenario: token inválido não escapa do limite

- **WHEN** uma requisição traz um JWT forjado que não decodifica
- **THEN** o throttle SHALL usar o IP como chave
- **AND** a requisição SHALL ser rejeitada pela autenticação independentemente do throttle

#### Scenario: decodificação do token no throttle não consulta o banco

- **WHEN** o bloco de throttle processa uma requisição autenticada
- **THEN** ele SHALL extrair apenas `sub` e `jti` do JWT
- **AND** SHALL NOT executar consulta a `users`

### Requirement: Limites por classe de endpoint de domínio

O sistema SHALL aplicar limites distintos por classe de operação, configuráveis por
variável de ambiente: leitura 300/min, escrita 120/min, criação em lote de robôs 10/min,
avanço de tarefa 60/min, autenticação 5/min e geração de relatório 5/min, por identidade.

#### Scenario: criação em lote é limitada separadamente

- **WHEN** um usuário dispara a 11ª chamada de criação em lote de robôs no mesmo minuto
- **THEN** a resposta SHALL ser 429
- **AND** as leituras do mesmo usuário no mesmo minuto SHALL continuar sendo atendidas

#### Scenario: throttle de autenticação usa os paths de D4

- **WHEN** os limites são carregados
- **THEN** eles SHALL referenciar os endpoints de autenticação definidos por
  `identity-and-auth` (D4)
- **AND** SHALL NOT referenciar `/api/v1/auth/login` do magic-link removido

#### Scenario: relatório pesado não derruba o banco

- **WHEN** um usuário solicita 6 gerações de relatório de comissionamento no mesmo minuto
- **THEN** a sexta SHALL responder 429

### Requirement: Resposta 429 utilizável pela fila offline

O sistema SHALL incluir `Retry-After` em segundos, além de `X-RateLimit-Limit`,
`X-RateLimit-Remaining` e `X-RateLimit-Reset`, em toda resposta 429, com corpo JSON em
pt-BR.

#### Scenario: cliente offline recua com valor do servidor

- **WHEN** a drenagem da fila de mutations (D7) recebe 429 com `Retry-After: 37`
- **THEN** o cliente SHALL aguardar ao menos 37 segundos antes da próxima tentativa
- **AND** SHALL NOT descartar a mutation da fila

#### Scenario: 429 não conta como poison message

- **WHEN** uma mutation da fila offline recebe 429 três vezes seguidas
- **THEN** ela SHALL permanecer na fila
- **AND** SHALL NOT ser marcada como poison message, que é reservado para 4xx de validação

#### Scenario: mensagem de erro é localizada

- **WHEN** uma resposta 429 é gerada
- **THEN** o corpo SHALL conter mensagem em pt-BR proveniente de `config/locales`
- **AND** SHALL NOT conter a string literal em inglês `Rate limit exceeded. Try again
  later.`
