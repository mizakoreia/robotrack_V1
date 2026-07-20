# audit-log-retention

## ADDED Requirements

### Requirement: Armazenamento particionado por mês

`audit_logs` SHALL ser uma tabela particionada por faixa sobre `ts`, com uma partição por
mês-calendário e uma partição `DEFAULT` de contenção. Um job SHALL manter partições
criadas com no mínimo **3 meses** de antecedência.

Nenhuma outra tabela SHALL declarar chave estrangeira para `audit_logs` — a PK composta
`(ts, id)` existe para viabilizar o particionamento e SHALL NOT ser alvo de referência.

#### Scenario: Registro cai na partição do seu mês
- **WHEN** um registro com `ts = 2026-03-14T18:07:00Z` é inserido
- **THEN** ele SHALL residir na partição `audit_logs_2026_03`

#### Scenario: Partições futuras existem com antecedência
- **GIVEN** a data corrente `2026-03-14`
- **WHEN** o job mensal de manutenção roda
- **THEN** SHALL existir partição para `2026-04`, `2026-05` e `2026-06`

#### Scenario: Partição DEFAULT recebendo linha dispara alerta
- **GIVEN** um registro que não coube em nenhuma partição mensal e foi para a `DEFAULT`
- **WHEN** o job mensal de manutenção roda
- **THEN** ele SHALL emitir alerta nomeando a contagem de linhas na partição `DEFAULT`
- **AND** SHALL NOT remover essas linhas

#### Scenario: Escrita nunca falha por partição faltante do mês corrente
- **GIVEN** um workspace concluindo uma tarefa a 100%
- **WHEN** o mês corrente não tem partição dedicada
- **THEN** o `INSERT` SHALL ser aceito pela partição `DEFAULT` e a conclusão da tarefa
  SHALL persistir normalmente

### Requirement: Retenção executada por DDL, nunca por DML

A poda de dados antigos SHALL ocorrer exclusivamente por `DETACH PARTITION` seguido de
`DROP TABLE` da partição destacada, executada pelo papel de migração fora do caminho de
request. O sistema SHALL NOT conceder `DELETE` em `audit_logs` a nenhum papel de aplicação
nem a nenhum papel operacional de rotina (§4.1 inv. 3).

#### Scenario: Nenhum papel de rotina possui DELETE
- **WHEN** o spec de auditoria de privilégios enumera os grants sobre `audit_logs`
- **THEN** SHALL encontrar zero papéis com `DELETE`, exceto o papel dono da tabela
- **AND** para o papel dono a trigger de imutabilidade SHALL continuar barrando `DELETE`
  de linha

#### Scenario: Job de retenção não emite DELETE
- **WHEN** o job de arquivamento processa uma partição elegível
- **THEN** o SQL executado SHALL conter `ALTER TABLE ... DETACH PARTITION` e
  `DROP TABLE`, e SHALL NOT conter nenhum `DELETE FROM audit_logs`

### Requirement: Arquivamento verificado antes de qualquer descarte

Antes de destacar e descartar uma partição, o sistema SHALL exportar todas as suas linhas
para storage frio em JSONL comprimido e SHALL verificar o arquivo comparando **contagem de
linhas** e **checksum** com a partição de origem. O `DROP` SHALL ocorrer somente após a
verificação passar.

A janela de retenção em armazenamento quente SHALL ser de **24 meses**; enquanto a
confirmação de produto sobre esse valor estiver pendente, o job SHALL arquivar e SHALL NOT
destacar.

#### Scenario: Falha de verificação preserva a partição
- **GIVEN** uma partição `audit_logs_2024_01` com 4.312 linhas
- **WHEN** o arquivo exportado contém 4.310 linhas
- **THEN** o job SHALL abortar, emitir alerta e SHALL NOT destacar a partição
- **AND** as 4.312 linhas SHALL continuar consultáveis

#### Scenario: Bucket de storage frio ausente não destrói nada
- **GIVEN** a variável `AUDIT_ARCHIVE_BUCKET` não configurada
- **WHEN** o job mensal de arquivamento roda
- **THEN** ele SHALL falhar com erro explícito nomeando a variável
- **AND** nenhuma partição SHALL ser destacada ou descartada

#### Scenario: Destacamento só ocorre após confirmação da janela
- **GIVEN** a janela de 24 meses ainda não confirmada pelo produto
- **WHEN** o job encontra uma partição de 30 meses de idade
- **THEN** ele SHALL arquivá-la e verificá-la
- **AND** SHALL NOT executar `DETACH` nem `DROP`

#### Scenario: Duplicidade de id é detectada na varredura
- **GIVEN** duas linhas com o mesmo `id` uuid em partições distintas
- **WHEN** o job de arquivamento executa a checagem de duplicidade
- **THEN** ele SHALL emitir alerta nomeando o `id` duplicado
- **AND** SHALL NOT remover nenhuma das linhas

### Requirement: Observabilidade do crescimento do log

O sistema SHALL expor métricas de contagem de linhas e tamanho em disco de `audit_logs`
por workspace e por partição, e SHALL alertar em (a) falha do job de arquivamento e
(b) queda de contagem total entre coletas consecutivas fora de uma janela de manutenção
declarada.

Estas métricas, o agendamento Sidekiq do job e as credenciais de storage frio SHALL ser
providos por `delivery-and-observability`.

#### Scenario: Queda inexplicada de contagem alerta
- **GIVEN** a contagem total de `audit_logs` em `812.400` na coleta anterior
- **WHEN** a coleta seguinte mede `640.100` sem janela de manutenção declarada
- **THEN** o sistema SHALL emitir alerta de possível perda de trilha de auditoria

#### Scenario: Queda durante manutenção declarada não alerta
- **GIVEN** uma janela de manutenção declarada com o `DROP` de `audit_logs_2024_01`
  registrado
- **WHEN** a contagem total cai exatamente pelo número de linhas arquivadas e verificadas
- **THEN** o sistema SHALL NOT emitir alerta
