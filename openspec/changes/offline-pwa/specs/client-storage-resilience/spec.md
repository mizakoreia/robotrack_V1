## ADDED Requirements

### Requirement: Todo acesso a armazenamento do navegador passa por `safeStorage` e nunca lança

O sistema SHALL rotear toda leitura e escrita de `localStorage`, `sessionStorage` e
`indexedDB` por um módulo único `safeStorage`, que SHALL capturar qualquer exceção e
devolver `null` (leitura) ou `false` (escrita). O sistema MUST NOT acessar esses globais
diretamente fora desse módulo, e a regra SHALL ser imposta por lint no CI (D7-11).

#### Scenario: Escrita que lança não derruba o app

- **WHEN** `localStorage.setItem` lança `QuotaExceededError` durante o boot do store de autenticação
- **THEN** `safeStorage.set` devolve `false`, nenhuma exceção escapa, e a aplicação renderiza normalmente

#### Scenario: Acesso direto ao global falha o CI

- **WHEN** um arquivo fora de `lib/storage/safeStorage.ts` referencia `localStorage`
- **THEN** a regra `no-restricted-globals` do ESLint falha o pipeline

#### Scenario: Leitura de chave ausente é indistinguível de leitura bloqueada

- **WHEN** `safeStorage.get('robotrack.theme')` é chamado com armazenamento bloqueado
- **THEN** devolve `null`, e o chamador aplica o valor padrão sem ramificar por tipo de erro

### Requirement: A sonda de armazenamento classifica o ambiente em três níveis no boot

O sistema SHALL, no boot, escrever e reler uma chave sentinela em cada meio de
armazenamento e SHALL classificar o ambiente como `persistent`, `session-only` ou
`memory-only`. O nível SHALL estar disponível ao restante do aplicativo antes da
primeira renderização da tela de login (§4.2, D7-11).

#### Scenario: Ambiente normal é classificado como persistente

- **WHEN** `localStorage` e IndexedDB aceitam escrita e leitura da sentinela
- **THEN** o nível é `persistent` e nenhum aviso é exibido

#### Scenario: Apenas `sessionStorage` disponível

- **WHEN** `localStorage` lança na escrita e `sessionStorage` funciona
- **THEN** o nível é `session-only`, a fila opera em memória, e o aviso informa que a sessão não persistirá ao fechar

#### Scenario: Tudo bloqueado cai para adapter em memória

- **WHEN** `localStorage`, `sessionStorage` e `indexedDB` falham
- **THEN** o nível é `memory-only` e um adapter em memória atende todas as chamadas de `safeStorage`

### Requirement: Navegador com armazenamento bloqueado ainda permite login, com aviso

O sistema SHALL permitir autenticação completa em qualquer nível de armazenamento. O
sistema MUST NOT bloquear, travar ou exibir tela em branco quando o armazenamento
estiver indisponível, e SHALL exibir um aviso persistente em pt-BR informando que a
sessão não persiste (§4.2).

#### Scenario: Login funciona em modo privado

- **WHEN** o usuário abre o RoboTrack em uma janela privada onde toda escrita de armazenamento lança e faz login com e-mail e senha
- **THEN** o login conclui, o token é mantido em memória, a aplicação navega para a Visão Geral, e um aviso informa "Seu navegador está bloqueando o armazenamento. Você pode usar o RoboTrack normalmente, mas a sessão não vai persistir ao fechar"

#### Scenario: Bloqueador de terceiro não trava o boot

- **WHEN** uma extensão bloqueia o acesso a `indexedDB` e o usuário abre o app
- **THEN** a aplicação renderiza a tela de login em vez de tela branca, e o console não registra exceção não capturada no boot

#### Scenario: Fechar a aba em `memory-only` derruba a sessão, como avisado

- **WHEN** o usuário faz login em `memory-only`, fecha a aba e reabre
- **THEN** a tela de login é exibida novamente e nenhuma promessa de sessão persistente foi feita

#### Scenario: Aviso é dispensável mas reaparece na sessão seguinte

- **WHEN** o usuário dispensa o aviso e recarrega a página ainda com armazenamento bloqueado
- **THEN** o aviso é exibido novamente, porque a dispensa não pôde ser persistida

### Requirement: A fila offline é desligada em `memory-only`, não degradada

O sistema MUST NOT enfileirar mutations quando o nível for `memory-only`. As mutations
SHALL ir direto à rede e SHALL falhar visivelmente quando não houver conectividade
(D7-11, PRODUCT.md — honestidade do estado).

#### Scenario: Escrita offline em `memory-only` falha visivelmente

- **WHEN** o nível é `memory-only`, o dispositivo está offline, e o usuário confirma um avanço
- **THEN** a requisição falha, uma mensagem de erro informa que a alteração não foi salva, e MUST NOT existir item algum em fila prometendo envio posterior

#### Scenario: Em `session-only` a fila existe mas avisa que não sobrevive ao reload

- **WHEN** o nível é `session-only` e o usuário enfileira duas mutations offline
- **THEN** as mutations ficam pendentes em memória e o aviso informa que elas serão perdidas se a página for recarregada

### Requirement: Sessão persistente é opcional pelo "manter conectado"

O sistema SHALL persistir a sessão entre reinícios do navegador somente quando o usuário
marcar "manter conectado" e o nível de armazenamento for `persistent`. Sem a marcação, a
sessão SHALL viver em `sessionStorage` (§4.2, D4).

#### Scenario: Manter conectado sobrevive ao reinício

- **WHEN** o usuário faz login com "manter conectado" marcado, fecha o navegador por completo e o reabre
- **THEN** a sessão está ativa e a Visão Geral abre sem passar pela tela de login

#### Scenario: Sem manter conectado a sessão morre com a aba

- **WHEN** o usuário faz login sem marcar "manter conectado" e fecha a aba
- **THEN** ao reabrir, a tela de login é exibida

#### Scenario: Marcação é ignorada com aviso quando não há armazenamento persistente

- **WHEN** o usuário marca "manter conectado" em nível `session-only`
- **THEN** o login conclui, a sessão não é persistida entre reinícios, e o aviso explica por quê

### Requirement: Preferência de tema é local e não segue a preferência do sistema

O sistema SHALL persistir a preferência de tema em `robotrack.theme` via `safeStorage` e
MUST NOT ler `prefers-color-scheme` para decidir o tema. O padrão SHALL ser escuro
(§4.2, §5.1).

#### Scenario: Tema claro escolhido persiste

- **WHEN** o usuário alterna para o tema claro e recarrega a página em nível `persistent`
- **THEN** o tema claro é aplicado antes da primeira pintura

#### Scenario: Sistema em claro não muda o padrão escuro

- **WHEN** o sistema operacional está em modo claro e não há preferência gravada
- **THEN** o aplicativo abre em escuro

#### Scenario: Tema volta ao padrão com armazenamento bloqueado

- **WHEN** o usuário alterna para claro em nível `memory-only` e recarrega
- **THEN** o aplicativo abre em escuro e nenhuma exceção é lançada

### Requirement: Token de convite vive em `sessionStorage` durante o fluxo de login

O sistema SHALL gravar o token de convite em `robotrack.invite_token` no
`sessionStorage` via `safeStorage` ao entrar por `/convite/:token`, e SHALL consumi-lo e
removê-lo após a autenticação (§4.2, D4).

#### Scenario: Convite sobrevive ao redirect do Google

- **WHEN** o usuário abre `/convite/abc123`, clica em "Entrar com Google" e retorna do callback
- **THEN** o token `abc123` é lido do `sessionStorage`, o convite é consumido, e a chave é removida

#### Scenario: Convite perdido por armazenamento bloqueado é resolvido sem silêncio

- **WHEN** o nível é `memory-only`, o usuário entra por `/convite/abc123`, autentica pelo redirect do Google, e o token não sobrevive
- **THEN** o aplicativo detecta que a rota de entrada era um convite e nenhum token está guardado, e instrui o usuário a reabrir o link do convite já autenticado, em vez de perder o convite em silêncio

#### Scenario: Token de convite não vai para a query string

- **WHEN** qualquer etapa do fluxo de login redireciona
- **THEN** o token de convite MUST NOT aparecer em query string de nenhuma URL navegada
