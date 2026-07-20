## ADDED Requirements

### Requirement: Ambientes nomeados com paridade de serviços

O sistema SHALL definir exatamente três ambientes — `development`, `staging` e
`production` — onde `staging` e `production` executam a **mesma imagem de container** e
diferem apenas por variáveis de ambiente e por escala de processo.

#### Scenario: staging e produção compartilham a imagem

- **WHEN** o pipeline constrói a imagem `robotrack-backend:abc1234` e a promove para
  `staging` e depois para `production`
- **THEN** o digest da imagem em execução nos dois ambientes SHALL ser idêntico
- **AND** nenhuma etapa de build SHALL ser reexecutada entre a promoção de `staging` e a
  de `production`

#### Scenario: divergência de esquema entre staging e produção é detectada

- **WHEN** o `schema_migrations` de `staging` contém a versão `20260801120000` e o de
  `production` não a contém, e um deploy de `production` é iniciado
- **THEN** a fase de release SHALL aplicar essa migration antes de qualquer processo
  `web` novo receber tráfego

### Requirement: Configuração de banco de dados sem credencial versionada

O sistema SHALL derivar a configuração de todos os ambientes de `DATABASE_URL` e SHALL
NOT conter usuário ou senha literais em `backend/config/database.yml`.

#### Scenario: seção de produção existe

- **WHEN** o processo `web` inicia com `RAILS_ENV=production` e `DATABASE_URL` definida
- **THEN** a aplicação SHALL conectar ao banco indicado pela URL
- **AND** SHALL NOT levantar `ActiveRecord::AdapterNotSpecified`

#### Scenario: nenhuma senha literal permanece no arquivo

- **WHEN** um teste automatizado lê `backend/config/database.yml`
- **THEN** o arquivo SHALL NOT conter a string `silas777` nem qualquer chave `password:`
  com valor literal não interpolado de ENV

#### Scenario: onboarding de desenvolvimento continua funcionando

- **WHEN** um desenvolvedor executa `bash create_dev_db.sh` num ambiente limpo
- **THEN** o script SHALL criar a role e o banco de desenvolvimento derivando os valores
  de `DATABASE_URL`
- **AND** SHALL falhar com mensagem explícita se `DATABASE_URL` estiver ausente, em vez de
  criar um banco com nome vazio

### Requirement: Topologia de processos de produção

O sistema SHALL declarar e executar processos separados para `web` (Puma), `worker`
(Sidekiq) e `release` (migrations), escaláveis de forma independente.

#### Scenario: worker escala sem reiniciar web

- **WHEN** o número de instâncias de `worker` passa de 1 para 3
- **THEN** os processos `web` em execução SHALL permanecer no ar sem reinício

#### Scenario: migration não roda no boot da aplicação

- **WHEN** dois processos `web` iniciam simultaneamente com uma migration pendente
- **THEN** nenhum dos dois SHALL executar `db:migrate`
- **AND** o processo SHALL falhar o readiness check informando "migrations pendentes", em
  vez de servir tráfego contra um esquema desatualizado

#### Scenario: imagem de produção não roda precompile de assets

- **WHEN** a imagem de produção do backend é construída
- **THEN** o build SHALL NOT executar `rails assets:precompile` (a aplicação é API-only)
- **AND** o container SHALL executar como usuário não-root

### Requirement: Isolamento dos bancos lógicos de Redis

O sistema SHALL usar três destinos Redis distintos — `REDIS_CACHE_URL`,
`REDIS_QUEUE_URL` e `REDIS_CABLE_URL` — e SHALL abortar o boot em `staging` e
`production` se dois deles resolverem para o mesmo par `(host, porta, banco lógico)`.

#### Scenario: colisão de banco lógico aborta o boot

- **WHEN** `REDIS_CACHE_URL=redis://r:6379/1` e `REDIS_QUEUE_URL=redis://r:6379/1` em
  `RAILS_ENV=production`
- **THEN** o processo SHALL encerrar com código de saída diferente de zero
- **AND** a mensagem SHALL nomear as duas variáveis em colisão

#### Scenario: política de eviction da fila é verificada

- **WHEN** a verificação operacional executa `CONFIG GET maxmemory-policy` no destino de
  `REDIS_QUEUE_URL`
- **THEN** o valor retornado SHALL ser `noeviction`
- **AND** a mesma verificação no destino de `REDIS_CACHE_URL` SHALL retornar uma política
  de eviction (`allkeys-lru` ou equivalente)

#### Scenario: desenvolvimento não é quebrado pelo isolamento

- **WHEN** um desenvolvedor roda com apenas `REDIS_URL` definida em
  `RAILS_ENV=development`
- **THEN** as três URLs SHALL assumir esse valor como default
- **AND** o boot SHALL prosseguir sem erro

### Requirement: ActionCable com adapter Redis e prefixo por ambiente

O sistema SHALL configurar o ActionCable com `adapter: redis` em `staging` e
`production`, apontando para `REDIS_CABLE_URL`, com `channel_prefix` que inclui o nome do
ambiente.

#### Scenario: broadcast não vaza entre ambientes

- **WHEN** `staging` e `production` apontam para a mesma instância Redis e um broadcast é
  publicado no `WorkspaceChannel` do workspace `W1` em `staging`
- **THEN** nenhum cliente conectado em `production` SHALL receber a mensagem
- **AND** as chaves usadas SHALL ser prefixadas por `robotrack_staging` e
  `robotrack_production` respectivamente

#### Scenario: prefixo ausente aborta o boot

- **WHEN** `cable.yml` de `production` não define `channel_prefix`
- **THEN** o boot SHALL falhar com mensagem nomeando `channel_prefix`

#### Scenario: dois processos web compartilham assinantes

- **WHEN** um cliente está conectado ao processo `web` A e uma mutação processada pelo
  processo `web` B publica um evento no `WorkspaceChannel` do mesmo workspace
- **THEN** o cliente conectado a A SHALL receber o evento

### Requirement: Fase de release para migrations com timeouts

O sistema SHALL executar `db:migrate` numa fase de release distinta, anterior à
substituição dos processos de aplicação, com `lock_timeout` de 5 segundos e
`statement_timeout` de 15 minutos na conexão de migration.

#### Scenario: lock não obtido falha o deploy rapidamente

- **WHEN** uma migration `ALTER TABLE tasks` não consegue o lock em 5 segundos porque uma
  transação longa está aberta
- **THEN** a fase de release SHALL falhar
- **AND** nenhum processo `web` novo SHALL ser promovido
- **AND** os processos `web` antigos SHALL continuar servindo tráfego

#### Scenario: falha de release não deixa deploy pela metade

- **WHEN** a fase de release termina com código diferente de zero
- **THEN** o deploy SHALL ser abortado antes de qualquer troca de processo

### Requirement: Regra expand/contract verificada no CI

O sistema SHALL rejeitar no CI qualquer migration destrutiva que não referencie
explicitamente o expand correspondente já aplicado em produção.

#### Scenario: contract sem marcador falha o CI

- **WHEN** uma migration contém `remove_column :tasks, :legacy_status` e não contém a
  linha `# contract-of: 20260801120000`
- **THEN** o spec de varredura de migrations SHALL falhar
- **AND** a mensagem SHALL nomear o arquivo e a operação destrutiva encontrada

#### Scenario: migration aditiva passa sem marcador

- **WHEN** uma migration contém apenas `add_column :tasks, :weight, :integer, null: true`
- **THEN** o spec de varredura SHALL passar

### Requirement: Runbook de rollback com ponto sem volta declarado

O sistema SHALL manter um runbook de rollback com três degraus ordenados — redeploy da
imagem anterior, kill switch por variável de ambiente e `db:rollback` — e SHALL declarar
por migration o ponto a partir do qual o rollback de esquema deixa de ser possível.

#### Scenario: rollback de código com esquema compatível

- **WHEN** a versão `abc1234` é promovida e apresenta erro, e apenas migrations de expand
  foram aplicadas desde `def5678`
- **THEN** redeployar `def5678` SHALL restaurar o serviço sem nenhuma alteração de esquema

#### Scenario: rollback após contract é recusado

- **WHEN** um operador tenta `db:rollback` de uma migration marcada como `contract`
- **THEN** a tarefa SHALL recusar a execução
- **AND** SHALL apontar o procedimento de restore de backup e o RPO declarado

#### Scenario: ensaio de rollback é pré-requisito do primeiro deploy

- **WHEN** o primeiro deploy de `production` é preparado
- **THEN** SHALL existir registro datado de um rollback executado com sucesso em
  `staging`

### Requirement: Backup verificado antes de migration destrutiva

O sistema SHALL exigir um backup lógico concluído e verificado imediatamente antes de
qualquer migration marcada como `contract`.

#### Scenario: contract sem backup recente é bloqueado

- **WHEN** uma migration `contract` é enfileirada e o backup mais recente tem mais de 1
  hora ou não passou na verificação de restauração
- **THEN** a fase de release SHALL abortar antes de executar a migration

#### Scenario: RPO é declarado e testado

- **WHEN** a rotina de verificação de backup roda
- **THEN** ela SHALL restaurar o backup mais recente num banco descartável e comparar a
  contagem de linhas de `workspaces`, `projects` e `audit_logs` com a origem
- **AND** SHALL registrar o RPO efetivo medido

### Requirement: Hospedagem estática do PWA com contrato de cache

O sistema SHALL servir o bundle React de armazenamento estático com CDN, com
`Cache-Control: no-store` para `index.html` e `sw.js`, e
`public, max-age=31536000, immutable` para assets com hash no nome.

#### Scenario: index.html nunca é servido de cache

- **WHEN** um smoke test pós-deploy faz `HEAD /index.html`
- **THEN** o header `Cache-Control` SHALL conter `no-store`

#### Scenario: asset com hash é imutável

- **WHEN** um smoke test faz `HEAD /assets/index-9f3a2b1c.js`
- **THEN** o header `Cache-Control` SHALL conter `max-age=31536000` e `immutable`

#### Scenario: resposta de API não é cacheada pelo CDN

- **WHEN** uma requisição autenticada `GET /api/v1/workspaces` passa pelo CDN
- **THEN** a resposta SHALL conter `Cache-Control: no-store`
- **AND** o CDN SHALL NOT armazenar a resposta

### Requirement: Registro único e tipado de configuração

O sistema SHALL declarar toda variável de ambiente num registro único
(`backend/config/env_schema.rb`) com nome, tipo, ambientes em que é obrigatória, default e
capacidade de origem, e SHALL abortar o boot em `staging` e `production` quando alguma
obrigatória estiver ausente.

#### Scenario: todas as ausentes são reportadas de uma vez

- **WHEN** `DEVISE_JWT_SECRET_KEY` e `REDIS_CABLE_URL` estão ausentes em
  `RAILS_ENV=production`
- **THEN** o boot SHALL falhar listando **as duas** variáveis numa única mensagem
- **AND** SHALL NOT abortar apenas na primeira

#### Scenario: default silencioso perigoso é eliminado

- **WHEN** `ACTION_CABLE_URL` está ausente em `RAILS_ENV=production`
- **THEN** o boot SHALL falhar
- **AND** SHALL NOT assumir `wss://example.com/cable`

#### Scenario: .env.example é gerado e não diverge

- **WHEN** uma variável é adicionada a `env_schema.rb` sem regenerar `.env.example`
- **THEN** o spec de conformidade SHALL falhar apontando o nome da variável faltante no
  arquivo

#### Scenario: variável opcional não derruba o boot

- **WHEN** `ALERT_PAGER_URL`, declarada como opcional, está ausente em `production`
- **THEN** o boot SHALL prosseguir
- **AND** alertas `critical` SHALL degradar para log e Sentry sem levantar exceção
