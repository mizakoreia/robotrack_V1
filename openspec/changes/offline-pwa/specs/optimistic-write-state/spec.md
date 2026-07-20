## ADDED Requirements

### Requirement: A sobreposição otimista é derivada da fila, não escrita no cache do servidor

O sistema SHALL manter no cache do React Query somente a verdade do servidor, e SHALL
aplicar as mutations pendentes por uma função pura `overlay(serverData,
pendingMutations)` no `select` dos hooks de leitura. O sistema MUST NOT usar
`setQueryData` para gravar valores otimistas no cache (D7-7, D9).

#### Scenario: Avanço offline aparece na tabela imediatamente

- **WHEN** o usuário confirma um avanço de 50 → 60 na tarefa `T` estando offline
- **THEN** a linha de `T` na tabela do robô exibe 60 imediatamente, sem esperar resposta do servidor

#### Scenario: Sobreposição desaparece exatamente quando o servidor já a contém

- **WHEN** a mutation de 50 → 60 é confirmada pelo servidor e o refetch traz `progress = 60`
- **THEN** o item sai da fila, a sobreposição deixa de ser aplicada, e o valor exibido continua 60 sem transição visível para outro número

#### Scenario: Reverter é a ausência da sobreposição

- **WHEN** a mutation de 50 → 60 é descartada pelo usuário após falhar em definitivo
- **THEN** o item sai da fila e a linha volta a exibir 50, sem qualquer rollback manual de snapshot

#### Scenario: Sobreposição sobrevive a remount e a reload

- **WHEN** o usuário confirma um avanço offline, navega para outra tela, volta, e recarrega a página
- **THEN** o valor otimista continua exibido, porque a fonte é a fila em IndexedDB e não um snapshot em memória

### Requirement: A sobreposição otimista vence o dado do servidor, inclusive evento ao vivo

O sistema SHALL dar precedência à sobreposição sobre o dado do servidor para qualquer
entidade com mutation pendente, e SHALL reaplicar a sobreposição após toda invalidação
de query, incluindo as originadas pelo `WorkspaceChannel` (D6, D7-7).

#### Scenario: Evento ao vivo não faz a UI piscar de volta

- **WHEN** há uma mutation pendente de 50 → 60 na tarefa `T`, e um evento do `WorkspaceChannel` invalida `['ws', W, 'robot', R, 'tasks']` disparando um refetch que devolve `progress = 50`
- **THEN** a tabela continua exibindo 60 e MUST NOT exibir 50 em nenhum quadro intermediário

#### Scenario: Mudança de outra pessoa em outra tarefa aparece normalmente

- **WHEN** há mutation pendente na tarefa `T1` e um evento ao vivo traz `progress = 80` para a tarefa `T2` do mesmo robô
- **THEN** `T1` mantém o valor otimista e `T2` passa a exibir 80

#### Scenario: Servidor volta a mandar quando a fila esvazia

- **WHEN** a mutation de `T` é confirmada e outra pessoa já havia avançado `T` para 70 depois disso
- **THEN** após a fila esvaziar, a tabela exibe o valor vindo do servidor e não o valor otimista anterior

### Requirement: O indicador de gravação nunca afirma que salvou o que está na fila

O sistema SHALL alimentar o indicador de gravação definido por `app-shell-navigation`
com os estados `salvando`, `salvo`, `pendente`, `erro` e `bloqueado`. O estado `salvo`
SHALL ser reportado somente quando não houver nenhum item em `pending`, `inflight` ou
`blocked` para o workspace corrente. O sistema MUST NOT reportar `salvo` para uma
mutation que só existe na fila (PRODUCT.md — honestidade do estado).

#### Scenario: Offline com fila não exibida como salvo

- **WHEN** o usuário confirma um avanço offline
- **THEN** o indicador exibe `pendente` com a contagem de alterações aguardando envio, e MUST NOT exibir `salvo`

#### Scenario: Salvo só depois da confirmação do servidor

- **WHEN** a última mutation pendente recebe 2xx e a fila fica vazia
- **THEN** o indicador transita de `salvando` para `salvo`

#### Scenario: Estado bloqueado é distinto de erro

- **WHEN** um item está `failed` em definitivo com 5 dependentes em `blocked`
- **THEN** o indicador exibe `bloqueado` com a contagem 6 e oferece o acesso à reconciliação, em vez de exibir `erro` genérico

#### Scenario: Fila de outro workspace não contamina o indicador

- **WHEN** há 3 itens pendentes do workspace `W1` e o usuário está no workspace `W2` sem pendências
- **THEN** o indicador exibe `salvo` no contexto de `W2`

#### Scenario: Sem armazenamento persistente o indicador não promete durabilidade

- **WHEN** o nível de armazenamento é `memory-only` e o usuário tenta uma escrita offline
- **THEN** o indicador exibe `erro` com a mensagem de que a alteração não foi salva, e MUST NOT exibir `pendente`
