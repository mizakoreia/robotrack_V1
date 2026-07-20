## ADDED Requirements

### Requirement: Recursos same-origin são servidos rede-primeiro com cache como fallback

O sistema SHALL responder toda requisição `GET` same-origin que não pertença à
allowlist de backend buscando primeiro na rede; em sucesso, a resposta SHALL ser
copiada para o cache da versão corrente e devolvida; em falha de rede, o sistema SHALL
devolver a entrada correspondente do cache. O sistema MUST NOT servir do cache uma
resposta que a rede poderia ter entregue (§4.3).

#### Scenario: Deploy novo não serve bundle antigo

- **WHEN** o cache contém `/assets/index-abc123.js` de um deploy anterior, o dispositivo está online, e o servidor passa a responder `/assets/index-def456.js` para o mesmo `index.html`
- **THEN** o `index.html` vem da rede, a requisição de `/assets/index-def456.js` vai à rede, e nenhuma resposta é servida a partir da entrada `index-abc123.js` do cache

#### Scenario: Offline serve o asset do cache

- **WHEN** `/assets/index-def456.js` já está no cache e a rede está indisponível
- **THEN** a requisição é respondida com a cópia em cache e a aplicação carrega

#### Scenario: Offline e sem cache resulta em falha, não em resposta vazia

- **WHEN** `/assets/chunk-nunca-visitado.js` nunca foi carregado e a rede está indisponível
- **THEN** o service worker devolve uma resposta de erro de rede e MUST NOT devolver uma resposta 200 vazia ou `undefined` que o navegador interpretaria como script válido

#### Scenario: Resposta de rede não-ok não sobrescreve o cache

- **WHEN** a rede responde `503` para `/assets/index-def456.js` e existe uma cópia em cache
- **THEN** a cópia em cache é devolvida e a entrada de cache MUST NOT ser substituída pelo corpo do `503`

### Requirement: Requisições ao backend nunca são interceptadas

O sistema MUST NOT chamar `event.respondWith` para requisições cujo `pathname` case
`^/(api|auth|cable|rails/active_storage)/`, nem para requisições de origem diferente da
do documento. Essas requisições SHALL seguir para a rede ao vivo com o comportamento
nativo do navegador (§4.3).

#### Scenario: `/api/v1/...` nunca é atendida pelo cache

- **WHEN** um `GET /api/v1/workspaces/W/projects` é disparado com o dispositivo offline
- **THEN** o handler de `fetch` do service worker retorna sem chamar `respondWith`, a requisição falha com erro de rede, e nenhuma entrada de `/api/v1/` existe no cache

#### Scenario: Same-origin não protege a API

- **WHEN** a API é servida no mesmo host do SPA e um `GET /api/v1/robots/R` é disparado online
- **THEN** a requisição não é interceptada, apesar de `url.origin === self.location.origin`

#### Scenario: Login não é quebrado pelo service worker

- **WHEN** `POST /auth/v1/session` é disparado com o service worker ativo
- **THEN** a requisição não é interceptada e o header `Authorization` e o corpo chegam intactos ao servidor

#### Scenario: WebSocket do ActionCable passa direto

- **WHEN** o cliente abre `/cable?token=...` para o `WorkspaceChannel`
- **THEN** a requisição de upgrade não é interceptada e a conexão WebSocket é estabelecida

#### Scenario: Cross-origin de terceiro passa direto

- **WHEN** a API está em `https://api.robotrack.app` e o SPA em `https://app.robotrack.app`
- **THEN** requisições para `api.robotrack.app` não são interceptadas

### Requirement: Métodos não-GET passam direto

O sistema MUST NOT interceptar requisições cujo método seja diferente de `GET` (§4.3).

#### Scenario: POST de avanço não é interceptado

- **WHEN** `POST /api/v1/tasks/T/advances` é disparado
- **THEN** o handler retorna sem chamar `respondWith`

#### Scenario: POST same-origin fora da API também passa direto

- **WHEN** um `POST` é disparado para um caminho same-origin fora da allowlist de backend
- **THEN** o handler retorna sem chamar `respondWith`, porque a regra de método precede a de rota

### Requirement: Navegação offline cai no documento principal em cache

O sistema SHALL, quando uma requisição de navegação (`request.mode === 'navigate'` ou
`Accept` contendo `text/html`) falhar na rede, responder com a entrada de `/index.html`
do cache da versão corrente (§4.3).

#### Scenario: Rota profunda abre offline

- **WHEN** o usuário abre `/projetos/P/celulas/C/robos/R` estando offline e `/index.html` está em cache
- **THEN** o `/index.html` em cache é devolvido com status 200 e o roteador do SPA resolve a rota no cliente

#### Scenario: Navegação sem shell em cache falha explicitamente

- **WHEN** o usuário abre `/` offline em uma instalação em que `/index.html` nunca foi cacheado
- **THEN** o service worker devolve erro de rede e a tela offline nativa do navegador aparece

### Requirement: Nova versão ativa imediatamente e limpa caches antigos

O sistema SHALL chamar `skipWaiting()` no evento `install` e, no evento `activate`,
SHALL apagar todo cache cujo nome seja diferente do da versão corrente e então chamar
`clients.claim()`. O nome do cache SHALL derivar do hash do build (§4.3).

#### Scenario: Caches de versões anteriores desaparecem

- **WHEN** o cache `robotrack-abc123` existe e um service worker com `CACHE_NAME = 'robotrack-def456'` ativa
- **THEN** após o `activate`, `caches.keys()` contém apenas `robotrack-def456`

#### Scenario: Cache do PWA legado é removido

- **WHEN** o dispositivo tem o cache `robotrack-v9-cache-v25` deixado pelo PWA legado e o service worker novo ativa
- **THEN** `robotrack-v9-cache-v25` é apagado e o `index.html` legado deixa de ser servível

#### Scenario: Cliente já aberto é assumido sem recarregar

- **WHEN** uma aba já estava aberta com a versão anterior e a nova ativa
- **THEN** `clients.claim()` faz o novo service worker controlar aquela aba e o cliente exibe o aviso de versão nova disponível

#### Scenario: Duas versões nunca coexistem servindo caches distintos

- **WHEN** dois deploys ocorrem em sequência rápida e três abas estão abertas
- **THEN** após o `activate` do último, existe exatamente um cache e todas as abas são controladas pelo mesmo service worker

### Requirement: O arquivo do service worker não pode ser cacheado pela infraestrutura

O sistema SHALL exigir que `sw.js` seja servido com `Cache-Control: no-cache,
must-revalidate`, e a configuração de deploy SHALL ser verificada automaticamente.

#### Scenario: Header de deploy é verificado

- **WHEN** o teste de fumaça de deploy executa `HEAD /sw.js` contra o ambiente publicado
- **THEN** o header `Cache-Control` contém `no-cache` e o teste falha o pipeline se contiver `max-age` maior que zero
