# localized-string-management

## ADDED Requirements

### Requirement: Catálogo pt-BR de backend em arquivos por domínio

O sistema SHALL manter todas as strings pt-BR do backend em
`config/locales/pt-BR.notifications.yml`, `pt-BR.audit.yml`, `pt-BR.report.yml` e
`pt-BR.errors.yml`, com `I18n.default_locale = :'pt-BR'` e
`I18n.available_locales` contendo **um único** item (D14).

#### Scenario: Locale único e sem fallback silencioso
- **WHEN** `I18n.t('audit.chave.inexistente')` é chamado
- **THEN** SHALL levantar erro em ambiente de teste e desenvolvimento — devolver
  `translation missing: ...` como string faria esse texto ser **persistido** numa
  linha de auditoria imutável

#### Scenario: Interpolação faltante é erro, não texto cru
- **WHEN** o template é `Tarefa %{tarefa} concluída por %{autor}` e o chamador
  fornece apenas `tarefa`
- **THEN** SHALL levantar `I18n::MissingInterpolationArgument` — a alternativa é o
  usuário final ver literalmente `%{autor}` numa notificação, e o log de auditoria
  guardar isso para sempre

#### Scenario: Toda chave definida é usada e toda chave usada existe
- **WHEN** o sweep de completude roda sobre os quatro arquivos
- **THEN** SHALL falhar tanto para chave referenciada e inexistente quanto para
  chave definida e órfã — a chave órfã é sintoma de um caminho que voltou a
  construir a string como literal

### Requirement: Escrita de mensagem persistida por chave, argumentos, snapshot e versão

O sistema SHALL persistir, em `notifications` e `audit_logs`, quatro campos de
mensagem: `message_key`, `message_args` (`jsonb`), `message` (texto renderizado no
momento da escrita, ≤ 500 chars) e `format_version` (`integer`). A **exibição** SHALL
usar `message` (D-QA-8).

#### Scenario: Alterar o catálogo não reescreve o passado
- **WHEN** uma linha de auditoria foi gravada com
  `message = "Status alterado de Pendente para Concluído por Ana"` e, meses depois,
  o template de `audit.task.status_changed` é reescrito
- **THEN** a linha antiga SHALL continuar exibindo o texto original — renderizar em
  leitura reescreveria retroativamente o texto de todo o histórico, contornando por
  fora o `REVOKE UPDATE, DELETE` de D12

#### Scenario: Chave e argumentos ficam disponíveis para reprocessamento
- **WHEN** a mesma linha é inspecionada
- **THEN** `message_key` SHALL ser `audit.task.status_changed` e `message_args`
  SHALL conter `{"de":"Pendente","para":"Concluído","autor":"Ana"}` — o snapshot
  sozinho é o que o legado fazia, e torna impossível distinguir uma linha do
  catálogo de um literal digitado num service

#### Scenario: Chave inválida é rejeitada pelo banco
- **WHEN** um `INSERT` direto grava `message_key = 'Tarefa concluída'`
- **THEN** o `CHECK (message_key ~ '^[a-z][a-z0-9_.]*$')` SHALL abortar — a
  invariante mora na constraint, não na validação do model, que se contorna por
  console

#### Scenario: `message_key` nula é rejeitada
- **WHEN** um `INSERT` grava `message` sem `message_key`
- **THEN** o `NOT NULL` SHALL abortar

#### Scenario: Mensagem acima de 500 caracteres é truncada na escrita, não na leitura
- **WHEN** os argumentos produzem um texto renderizado de 640 chars
- **THEN** `message` SHALL ser persistida com no máximo 500 chars (§2.7), **E**
  `message_args` SHALL conter os valores completos — truncar na leitura faria o
  mesmo registro exibir tamanhos diferentes conforme a tela

### Requirement: `Rt::Message` como único caminho de escrita de mensagem

O sistema SHALL prover `Rt::Message.render(key, **args)` retornando
`[texto, format_version]`, e SHALL garantir que nenhum service de notificação,
auditoria ou relatório construa a mensagem por outro caminho.

#### Scenario: Literal em caminho de notificação reprova o CI
- **WHEN** o sweep varre `app/services/notifications/` e encontra
  `"Você foi atribuído à tarefa"` fora de uma linha marcada `# rt:i18n-ok`
- **THEN** SHALL falhar nomeando arquivo e linha

#### Scenario: O sweep pega literal acentuado e literal de 3+ letras
- **WHEN** o sweep encontra `"Concluido"` (sem acento) num service de auditoria
- **THEN** SHALL falhar — restringir o sweep a caracteres acentuados deixaria passar
  exatamente as strings escritas com erro de acentuação, que são as que mais
  precisam vir do catálogo

#### Scenario: Interpolação por concatenação também reprova
- **WHEN** um service monta `"Progresso de " + task.desc + " atualizado"`
- **THEN** o sweep SHALL falhar — a concatenação é a forma mais comum de escapar de
  um sweep que só procura string literal inteira

#### Scenario: Os três caminhos são varridos, não só um
- **WHEN** o sweep roda
- **THEN** SHALL cobrir `app/services/notifications/`, `app/services/audit_logs/` e
  `app/services/reports/` — o relatório é o caminho onde a string vai para um
  documento que o cliente assina (§3.8)

### Requirement: `format_version` sobe quando a assinatura de argumentos muda

O sistema SHALL versionar cada namespace do catálogo e SHALL falhar o CI quando o
conjunto de interpolações de uma chave mudar sem a versão do namespace subir,
comparando com um snapshot de assinaturas versionado no repositório.

#### Scenario: Adicionar um argumento sem subir a versão reprova
- **WHEN** `notifications.task.assigned` passa de `%{tarefa}` para
  `%{tarefa} em %{robo}` e `format_version` do namespace permanece
- **THEN** o CI SHALL falhar — as linhas antigas não têm `robo` em `message_args` e
  não podem ser rerrenderizadas; é exatamente isso que a versão registra

#### Scenario: Mudança apenas redacional não exige nova versão
- **WHEN** o template muda de `Tarefa %{tarefa} concluída` para
  `%{tarefa} foi concluída`, com o mesmo conjunto de argumentos
- **THEN** o CI SHALL passar sem incremento de versão — versionar redação
  transformaria o campo em ruído e ninguém o manteria

#### Scenario: A versão gravada é a do momento da escrita
- **WHEN** uma notificação é criada com o namespace na versão `2`
- **THEN** a linha SHALL persistir `format_version = 2`, mesmo que o namespace vá a
  `3` depois

### Requirement: Módulo único de strings no frontend com chaves tipadas

O sistema SHALL concentrar todas as strings de UI em
`frontend/src/lib/i18n/pt-BR.ts`, exportando um objeto `as const` e uma função
`t(key, params)` cujo tipo de `key` deriva do objeto, de modo que chave inexistente
seja erro de **compilação**.

#### Scenario: Chave inexistente quebra o type-check
- **WHEN** um componente chama `t('robo.titulo.inexistente')`
- **THEN** `tsc` SHALL falhar — um erro em runtime só aparece na tela em que ninguém
  navegou durante a revisão

#### Scenario: Parâmetro faltante quebra o type-check
- **WHEN** a chave declara `{robo: string}` e o componente chama `t('...', {})`
- **THEN** `tsc` SHALL falhar

#### Scenario: Texto pt-BR solto em JSX reprova o sweep
- **WHEN** o sweep de Vitest varre `src/features/**` e `src/components/**` e
  encontra um nó de texto JSX com `Nenhuma tarefa encontrada` fora de `t(...)`
- **THEN** SHALL falhar nomeando arquivo e linha

#### Scenario: Nenhuma biblioteca de i18n é adicionada
- **WHEN** o orçamento de bundle inspeciona o grafo do entry
- **THEN** SHALL não conter `i18next` nem `react-intl` — 40 KB para um locale único,
  sem plural além do que `Intl.PluralRules` resolve, não paga (referência cruzada:
  `performance-budgets`)

### Requirement: Rótulos de métrica de progresso vêm do catálogo

O sistema SHALL expor os rótulos das duas métricas de D15 como chaves do catálogo em
ambos os lados, de modo que o mesmo termo apareça idêntico na UI, no `aria-label` do
anel e no relatório assinado.

#### Scenario: O mesmo rótulo em três superfícies
- **WHEN** o rótulo do progresso ponderado é lido na UI do card, no `aria-label` do
  anel e no corpo do relatório
- **THEN** as três SHALL produzir exatamente a mesma string, resolvida da mesma
  chave — três literais equivalentes divergem no primeiro ajuste de redação e o
  cliente recebe dois nomes para a mesma métrica no mesmo documento

#### Scenario: Número de progresso sem rótulo resolvido reprova
- **WHEN** um componente renderiza `62%` sem passar pela chave de rótulo
- **THEN** o sweep de D15 SHALL falhar (referência cruzada: `progress-rollup`)
