## Why

O RoboTrack é usado dentro de um galpão de solda, com celular na mão e sinal
intermitente. A promessa do produto não é "funciona quando tem rede": é que o
engenheiro registra um avanço às 14h no fundo da célula, guarda o telefone, e às 17h
— quando o Wi-Fi volta no escritório — aquele avanço já está no relatório assinado
**com a hora em que aconteceu**. Se isso falhar, o registro de comissionamento deixa
de ser um registro.

Cobre `ESPECIFICACAO.md` §4.2 (persistência local e offline) e §4.3 inteiro
(estratégia de cache do app instalável). É dona da decisão transversal **D7**.
Depende de `robot-task-table` (Onda 9) e é a **ponta do caminho crítico**.

**Esta é a maior lacuna do plano anterior.** O Firestore entregava de graça quatro
coisas distintas, e o WBS anterior as substituiu por três linhas de tabela:

| O que o Firestore dava | O que o porte precisa construir |
|---|---|
| Cache local write-through | Service worker network-first + cache de leitura do React Query |
| Fila automática de mutations | Fila persistida em IndexedDB, ordenada, com dependências, teto e poison handling |
| Resolução automática de conflito | `lock_version` + 409 explícito (`progress-advances`) + política de reconciliação aqui |
| Coordenação entre abas | Eleição de líder por Web Locks + fan-out por `BroadcastChannel` |

Quatro traduções conscientes de Firebase → Rails/React:

- **Persistência offline do SDK → fila de mutations própria.** O SDK do Firestore
  enfileirava escritas sozinho e as reenviava na reconexão. Nada em axios faz isso.
  A fila passa a ser um artefato de primeira classe do cliente, com esquema
  versionado em IndexedDB.
- **Ids gerados pelo SDK offline → uuid cliente-gerado em toda tabela de domínio
  (D1).** Este é o ponto que tornava o plano anterior **estruturalmente impossível**:
  lá, só os avanços tinham id gerado no cliente. Criar um robô offline não produzia
  id, logo não havia contra o que enfileirar um avanço em uma tarefa desse robô. Com
  D1 o grafo passa a ser exprimível.
- **`serverTimestamp()` → `recorded_at` do cliente (D8).** Carimbado no instante em
  que a pessoa confirma o modal, **não** no instante do envio.
- **`onSnapshot` reconciliando sozinho → ActionCable + invalidação (D6)** com uma
  camada de sobreposição otimista que impede a UI de piscar de volta quando um evento
  ao vivo chega enquanto ainda há mutação pendente na fila.

## What Changes

**Service worker (§4.3)** — cada bullet da spec vira requisito verificável:

- Todo recurso **same-origin** é servido **rede primeiro, cache como fallback**.
  Nunca servir bundle antigo depois de um deploy.
- Requisições ao backend (`/api/**`, `/auth/**`, `/cable`) **nunca são
  interceptadas** — `fetch` não é chamado com `respondWith`, a requisição segue para a
  rede ao vivo. Interceptá-las quebraria login e sincronização. Isso vale **inclusive
  quando a API está em outra origem** em produção.
- Métodos não-GET passam direto, sem exceção.
- Navegação offline cai no `index.html` em cache (SPA shell).
- `skipWaiting` + `clients.claim` na ativação, e **apagar todo cache cujo nome não
  seja o da versão corrente**.
- Registro do SW e prompt de recarga quando uma versão nova assume.

**Fila de mutations (§4.2)**:

- Store `mutations` em IndexedDB (`robotrack`, versão de esquema explícita), ordenada
  por `seq` monotônico, com estados `pending | inflight | blocked | failed | done`.
- **Grafo de dependência entre itens.** Toda mutation declara `depends_on: uuid[]`.
  "Criar robô R" precede "registrar avanço na tarefa T de R". Falha permanente de R
  marca os dependentes como `blocked`, **não** trava o resto da fila.
- **Idempotência**: o uuid do recurso (D1) **é** a chave. Nenhum header
  `Idempotency-Key`, nenhuma tabela de chaves com TTL — o replay tardio de um cliente
  que ficou uma semana offline continua idempotente.
- **Teto de tamanho** (500 itens / 5 MB) com rejeição na ponta de entrada e aviso
  explícito, nunca descarte silencioso do que já está enfileirado.
- **Poison message**: backoff exponencial, classificação de erro
  (retryable / permanente), e quarentena após teto de tentativas.
- **Atualização otimista** por sobreposição derivada da fila, reaplicada após toda
  invalidação de query — inclusive as vindas do `WorkspaceChannel` (D6).
- **`recorded_at` do cliente** (D8) carimbado no enfileiramento.
- **Coordenação entre abas**: exatamente uma aba drena a fila por vez (Web Locks);
  as demais recebem o estado por `BroadcastChannel`.

**Sessão e degradação (§4.2)**:

- Módulo único `safeStorage` — toda leitura/escrita de `localStorage` e
  `sessionStorage` do app passa por ele; nunca lança.
- Sonda de armazenamento no boot classifica o ambiente em `persistent` /
  `session-only` / `memory-only`.
- Em `memory-only` o app **funciona e permite login**, apenas avisa que a sessão não
  persiste e que a fila offline está desligada. **BREAKING** em relação ao template:
  o acesso direto a `localStorage` em `lib/api/client.ts` e nos stores Zustand é
  substituído pelo `safeStorage`.
- Preferência de tema e token de convite (`sessionStorage`) atravessam o mesmo módulo.

**Indicador honesto de gravação**: alimentamos o contrato `salvando | salvo | erro`
já definido por `app-shell-navigation`, estendido com `pendente` (na fila, ainda não
no servidor) e `bloqueado`. "Honestidade do estado" é princípio de produto: a UI
**MUST NOT** dizer "salvo" para algo que está só na fila.

### Não-objetivos

- **Cache de resposta de API no service worker.** Não fazemos, de propósito (§4.3).
  Leitura offline vem do cache em memória/persistido do React Query, não do SW.
- **Background Sync API / Periodic Sync.** Ver `design.md` D7-9: cobertura de
  navegador insuficiente para o parque (iOS Safari não implementa) e a fila precisaria
  existir de qualquer forma. O drain é disparado por `online`, foco e timer.
- **Resolução de conflito por merge automático.** `lock_version` e o 409 são de
  `progress-advances`. Aqui só decidimos o que a fila faz com um 409.
- **CRDT ou sincronização bidirecional de documento.** O modelo é fila de comandos,
  não replicação de estado.
- **Endpoints, policies e constraints do servidor.** Consumimos o contrato de
  idempotência de `commissioning-hierarchy` (D-H2) e de `progress-advances`; não o
  redefinimos.
- **Contrato visual do indicador de gravação** — é `app-shell-navigation`. Somos o
  produtor dos estados, não o desenhista.
- **Publicação de eventos e o `WorkspaceChannel`** — é `realtime-collaboration` (D6).
  Aqui só definimos a precedência entre evento ao vivo e sobreposição otimista.
- **Manifesto PWA, ícones e prompt de instalação** — `design-system` e
  `delivery-and-observability`. Usamos o que existe.
- **Modo offline para leitura de dados nunca visitados.** Só é navegável offline o
  que já foi carregado nesta instalação.

### Impact

- **Frontend**: novo `frontend/src/lib/offline/` (fila, dependências, drain, leader,
  broadcast, safeStorage), novo `frontend/public/sw.js` gerado pelo build, alteração
  em `lib/api/client.ts` (acesso a storage e enfileiramento), alteração nos hooks de
  mutation de `robot-task-table` e `commissioning-hierarchy` para passarem pela fila.
- **Backend**: nenhuma mudança de esquema. Depende de idempotência por uuid já
  entregue por D1/D-H2 e de `recorded_at` já entregue por D8.
- **Entrega** (`delivery-and-observability`): o `sw.js` **MUST** ser servido com
  `Cache-Control: no-cache` e a versão do cache **MUST** vir do hash do build. Sem
  isso, §4.3 ("nunca servir código antigo") falha na própria camada do SW.

## Capabilities

### New Capabilities

- `service-worker-caching`: estratégia de cache do app instalável (§4.3) — network-first
  same-origin, não-interceptação absoluta do backend, passagem direta de escritas,
  fallback de navegação, ativação imediata e limpeza de caches antigos.
- `offline-mutation-queue`: fila persistida em IndexedDB (§4.2) — ordem, grafo de
  dependência entre itens, idempotência por uuid, `recorded_at` do cliente, teto de
  tamanho, poison message, drain, coordenação entre abas e reconciliação com o
  servidor.
- `optimistic-write-state`: sobreposição otimista sobre o cache do React Query, sua
  precedência sobre eventos ao vivo (D6), e os estados do indicador honesto de
  gravação.
- `client-storage-resilience`: `safeStorage`, sonda de armazenamento, degradação
  graciosa quando o navegador bloqueia armazenamento, preferência de tema local e
  token de convite em `sessionStorage`.

### Modified Capabilities

Nenhuma. `openspec/specs/` está vazio.
