# Spec — `client-server-state-conventions`

Materializa **D9**. Vinculante para `hierarchy-screens`, `robot-task-table`,
`my-tasks-view`, `commissioning-report`, `workspace-settings`, `in-app-notifications`,
`realtime-collaboration` e `offline-pwa`.

## ADDED Requirements

### Requirement: React Query é o único mecanismo de leitura de estado de servidor

Toda leitura de dado de domínio SHALL ocorrer por hook de React Query. Nenhum componente
MUST chamar `apiClient` diretamente, e nenhum dado de domínio MUST ser buscado em
`useEffect` e guardado em `useState`.

#### Scenario: Componente não importa o cliente HTTP

- **WHEN** os módulos sob `frontend/src/app/pages/` e `frontend/src/components/` são
  varridos
- **THEN** nenhum deles importa `lib/api/client` ou `lib/api/endpoints` diretamente

#### Scenario: Leitura de domínio em useEffect é rejeitada

- **WHEN** um componente busca a lista de projetos com `useEffect` + `useState`
- **THEN** a verificação automatizada de convenção falha, identificando o arquivo

#### Scenario: Estado de servidor não é copiado para o Zustand

- **WHEN** os stores de Zustand do projeto são varridos
- **THEN** nenhum deles declara campo que armazene projetos, células, robôs, tarefas,
  avanços ou notificações

### Requirement: Convenção de query key com prefixo de workspace obrigatório

Toda query de domínio SHALL usar key no formato `['ws', wsId, …]`, construída por uma
factory tipada e nunca por array literal. Coleções usam substantivo no plural; entidades
usam o singular seguido do identificador.

#### Scenario: Key de coleção segue a forma canônica

- **WHEN** a factory é chamada para a lista de projetos do workspace `betim`
- **THEN** ela retorna exatamente `['ws', 'betim', 'projects']`

#### Scenario: Key de coleção aninhada segue a forma canônica

- **WHEN** a factory é chamada para as tarefas do robô `r-42` do workspace `betim`
- **THEN** ela retorna exatamente `['ws', 'betim', 'robot', 'r-42', 'tasks']`

#### Scenario: Query registrada fora da forma canônica falha em desenvolvimento

- **WHEN** uma query de domínio é registrada com a key `['projects']` em ambiente de
  desenvolvimento ou teste
- **THEN** o guard de forma de key lança erro identificando a key ofensora

#### Scenario: Guard não derruba a aplicação em produção

- **WHEN** uma query de domínio com key `['projects']` é registrada em produção
- **THEN** o guard não lança, e reporta a ocorrência ao rastreio de erro

#### Scenario: Filtros de UI não entram na key

- **WHEN** o filtro segmentado da tabela do robô muda de "Todos" para "Em andamento"
- **THEN** a key permanece `['ws', 'betim', 'robot', 'r-42', 'tasks']`
- **AND** nenhuma nova requisição HTTP é emitida

#### Scenario: Filtro que muda o conjunto do servidor entra como último segmento

- **WHEN** a busca global (§3.7) é executada com o termo "solda" no workspace `betim`
- **THEN** a key é `['ws', 'betim', 'search', { q: 'solda' }]`

#### Scenario: Hooks moram no lugar canônico

- **WHEN** a árvore `frontend/src/features/` é varrida
- **THEN** todo hook de query de domínio está sob `features/<dominio>/api/`
- **AND** cada um desses módulos exporta a factory de keys do seu domínio

### Requirement: Política de cache e de repetição

O `QueryClient` SHALL ser criado num módulo próprio, acessível fora da árvore React, com
`staleTime` de 30 segundos, `gcTime` de 5 minutos, `refetchOnWindowFocus: false`,
`retry: 1` para queries e `retry: 0` para mutations.

#### Scenario: Defaults do cliente

- **WHEN** o `QueryClient` da aplicação é inspecionado
- **THEN** `queries.staleTime` é 30000, `queries.gcTime` é 300000,
  `queries.refetchOnWindowFocus` é `false` e `queries.retry` é 1
- **AND** `mutations.retry` é 0

#### Scenario: Mutations não são repetidas pelo React Query

- **WHEN** uma mutation de avanço `+10` falha com erro de rede
- **THEN** o React Query não a reenvia
- **AND** a repetição fica a cargo da fila offline, não produzindo `+20`

#### Scenario: O cliente é acessível fora da árvore React

- **WHEN** o handler de troca de workspace, que não é um componente, precisa do cliente
- **THEN** ele o obtém por importação do módulo, sem hook e sem contexto

### Requirement: Invalidação explícita e de escopo mínimo

Toda mutation SHALL declarar explicitamente as query keys que invalida, usando o prefixo
mais raso que ainda seja correto. Invalidar `['ws', wsId]` inteiro MUST NOT ocorrer fora
do fluxo de troca de workspace.

#### Scenario: Avanço de tarefa invalida o escopo do robô

- **WHEN** um avanço é registrado na tarefa `t-9` do robô `r-42` do workspace `betim`
- **THEN** `['ws', 'betim', 'robot', 'r-42']` é invalidada
- **AND** `['ws', 'betim', 'my-tasks']` é invalidada

#### Scenario: Invalidação de raiz de workspace é rejeitada

- **WHEN** uma mutation declara invalidar `['ws', 'betim']`
- **THEN** a verificação automatizada de convenção falha, apontando a mutation

#### Scenario: Evento do WorkspaceChannel encontra a key correspondente

- **WHEN** o `WorkspaceChannel` do workspace `betim` publica um evento de mutação no robô
  `r-42`
- **THEN** o cliente invalida `['ws', 'betim', 'robot', 'r-42']` usando a mesma factory de
  keys

#### Scenario: Evento de outro workspace é descartado

- **WHEN** chega um evento de Cable com `workspace_id = 'camacari'` enquanto o workspace
  corrente é `betim`
- **THEN** nenhuma invalidação é executada

### Requirement: Fronteira do estado de cliente

O Zustand SHALL guardar exclusivamente estado que não existe no servidor: tema, filtros e
agrupamento de UI, estado do shell, workspace corrente, fila offline, indicador de
persistência e sessão.

#### Scenario: Filtros de UI vivem no Zustand

- **WHEN** o filtro segmentado da tabela do robô é alterado
- **THEN** o valor é gravado no store de UI e nenhuma query é invalidada

#### Scenario: Nenhuma sincronização manual entre store e cache

- **WHEN** o código-fonte é varrido
- **THEN** nenhum store de Zustand escreve no `queryClient`, exceto o handler de troca de
  workspace e o de logout

### Requirement: Fonte única de verdade para o token de acesso

O token de acesso SHALL residir exclusivamente no store de auth persistido. O cliente HTTP
MUST NOT ler o token de `localStorage`; ele o obtém por acessor injetado no boot.

#### Scenario: O cliente HTTP não lê localStorage

- **WHEN** o módulo `lib/api/client.ts` é varrido
- **THEN** ele não contém referência a `localStorage`

#### Scenario: Requisição usa o token do store

- **WHEN** o store de auth contém o token `abc123` e uma requisição de domínio é emitida
- **THEN** o cabeçalho `Authorization` é `Bearer abc123`

#### Scenario: Logout invalida de verdade

- **WHEN** o usuário sai e o store de auth é limpo
- **THEN** a requisição seguinte é emitida sem cabeçalho `Authorization`
- **AND** as chaves `access_token` e `token` não existem em `localStorage`

#### Scenario: Migração das chaves legadas roda uma vez e as remove

- **WHEN** o navegador tem `localStorage.access_token = 'legado1'` e o store de auth está
  vazio no boot
- **THEN** o store passa a conter `legado1`
- **AND** `localStorage.access_token` é removido
- **AND** um segundo boot não altera nada

#### Scenario: Sem chave legada a migração é inócua

- **WHEN** o navegador não tem `access_token` nem `token` em `localStorage`
- **THEN** o boot conclui sem erro e o store permanece como estava

#### Scenario: Sem ciclo de import entre cliente HTTP e store

- **WHEN** o grafo de módulos é analisado
- **THEN** `lib/api/client.ts` não importa `store/authStore.ts`
