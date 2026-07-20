# Design — `offline-pwa` (dona da decisão D7)

## Context

O sistema legado é um PWA vanilla sobre Firestore. Quatro comportamentos que o
usuário percebe como "o app funciona no galpão" não estavam em nenhuma linha de
código do RoboTrack — eram do SDK do Firestore:

1. **Cache local write-through.** `setDoc` resolvia localmente e a UI atualizava antes
   de qualquer rede.
2. **Fila automática de mutations.** Escritas offline eram persistidas pelo SDK e
   reenviadas na reconexão, na ordem, sem código de aplicação.
3. **Resolução automática de conflito.** Last-write-wins por campo, no servidor.
4. **Coordenação entre abas.** A persistência multi-tab do SDK elegia uma aba primária
   e as demais compartilhavam a mesma visão.

Nenhuma sobrevive ao porte. Axios não enfileira, React Query não persiste mutations,
Postgres não faz last-write-wins e `IndexedDB` não coordena abas.

O plano anterior substituiu as quatro por três linhas de tabela. Pior: era
**estruturalmente impossível**, porque lá só `task_advances` tinha id gerável no
cliente. Sem uuid cliente-gerado em `robots` e `tasks`, criar um robô offline não
produzia id, e portanto não existia chave contra a qual enfileirar um avanço em uma
tarefa desse robô. **D1 é o pré-requisito de D7**, e é por isso que ela é dona de
`commissioning-hierarchy` e não daqui.

## Goals / Non-Goals

**Goals**

1. Um avanço registrado offline às 14h e sincronizado às 17h aparece na trilha e no
   relatório assinado como **14h** (D8).
2. Criar robô + registrar avanço numa tarefa dele, tudo offline, chega ao servidor na
   ordem correta e sem 404 de FK.
3. A mesma mutation entregue duas vezes cria **um** registro.
4. Uma mutation que falha permanentemente **não** trava a fila para sempre, e seus
   dependentes não viram lixo silencioso.
5. Nunca servir bundle antigo depois de um deploy; nunca servir `/api` do cache.
6. Storage bloqueado **não** trava o login.
7. A UI nunca afirma "salvo" para o que está só na fila.

**Non-Goals**

- Merge automático de conflito. 409 é decisão do usuário.
- Leitura offline de dados nunca visitados nesta instalação.
- Background Sync API (ver D7-9).
- Fila offline em modo `memory-only` (ver D7-11) — a garantia de durabilidade some,
  e prometê-la sem lastro seria pior que não oferecê-la.

## Decisions

### D7-1 — Bypass do backend por **allowlist de rota**, não por checagem de origem

O SW legado bypassava tudo que fosse cross-origin (`url.origin !== self.location.origin`)
porque o Firestore *era* cross-origin. No porte a API pode ser **same-origin** (monólito
atrás do mesmo host) ou cross-origin (SPA em CDN, API em subdomínio). Herdar a checagem
de origem faria o SW **interceptar `/api/v1/...` em produção same-origin** e violar §4.3
no dia em que o deploy mudar de topologia.

Regra: o handler de `fetch` retorna **sem chamar `event.respondWith`** quando
`url.pathname` casa `^/(api|auth|cable|rails/active_storage)/` **ou** quando
`url.origin !== self.location.origin`. Não passar por `respondWith` é o que garante o
comportamento nativo do browser — inclusive streaming, `Authorization` e o upgrade de
WebSocket do `/cable`.

**Onde a invariante mora:** teste unitário do SW que dispara um `FetchEvent` sintético
para `/api/v1/robots` e afirma que `respondWith` **não** foi chamado; mais um teste E2E
que corta a rede e verifica que a chamada de API **falha** (em vez de responder do
cache) — porque responder do cache aqui é o bug, não a funcionalidade.

**Alternativa descartada — cachear GETs de `/api` com stale-while-revalidate.** Daria
leitura offline "de graça", mas serviria dado de outro workspace após uma troca de
tenant (o SW não conhece `workspace_id`), e serviria resposta autenticada com um token
que já foi revogado por denylist (D4). O cache de leitura fica no React Query, que
conhece a query key `['ws', wsId, ...]` e é descartado na troca de workspace
(`app-shell-navigation`).

### D7-2 — Network-first para todo same-origin, versão do cache = hash do build

Assets do Vite são content-hashed, o que tentaria a usar cache-first para `/assets/*`.
Não fazemos: §4.3 diz "todo recurso próprio, rede primeiro". Ganho de latência não
compensa a classe de bug em que `index.html` novo referencia um chunk que o SW ainda
não tem e o app fica em tela branca.

`CACHE_NAME = 'robotrack-' + __BUILD_HASH__`, injetado pelo build. No `activate`,
`caches.keys()` → apagar tudo que não seja o corrente → `clients.claim()`. No `install`,
`skipWaiting()`.

**Buraco de entrega (cita `delivery-and-observability`):** o próprio `sw.js` **MUST**
ser servido com `Cache-Control: no-cache, must-revalidate`. Se o CDN cachear o `sw.js`
por 24h, "nova versão ativa imediatamente" é falso e §4.3 falha na camada que deveria
garanti-la. Isso é configuração de deploy, não código.

**Alternativa descartada — Workbox.** Traz precache manifest, versionamento e rotas
prontas, mas o comportamento que precisamos é ~60 linhas e a regra mais importante
(não interceptar o backend) é uma **ausência** de rota, que uma biblioteca de
roteamento torna mais fácil de acidentalmente reintroduzir. Dependência maior que o
problema.

### D7-3 — A fila é um log de comandos, não um diff de estado

Cada item é `{id, seq, kind, resource_uuid, workspace_id, method, url, body,
depends_on[], recorded_at, state, attempts, next_attempt_at, last_error}`.

`seq` é um inteiro monotônico por dispositivo (`autoIncrement` do object store), e a
ordem de drenagem é `seq` crescente **restrita pelo grafo** (D7-4). Guardar comandos e
não estado é o que faz "+10 duas vezes offline" virar **dois** avanços de +10 na
trilha, que é o que §2.4 exige — a trilha é append-only e cada ação é uma entrada.

**Alternativa descartada — coalescer mutations da mesma entidade.** Reduziria a fila,
mas destruiria a trilha de comissionamento, que é o produto.

### D7-4 — Dependência é **declarada** pelo produtor, resolvida por grafo na drenagem

Esta é a parte que o plano anterior não tinha.

Quem enfileira declara `depends_on`. Não inferimos por heurística de URL. Exemplo do
cenário canônico, tudo offline:

| seq | kind | resource_uuid | depends_on |
|---|---|---|---|
| 1 | `robot.create` | `R` | `[]` |
| 2 | `task.create` | `T` | `[R]` |
| 3 | `advance.create` | `A` | `[T]` |

Regra de drenagem: um item só é elegível quando **todos** os uuids em `depends_on`
estão em `resolved_uuids` — o conjunto persistido dos recursos que o servidor já
confirmou (2xx). Ao 2xx de `robot.create R`, `R` entra em `resolved_uuids` e o item 2
destrava. Itens não elegíveis são pulados, **não** bloqueiam o `seq` seguinte: um
`project.rename` independente enfileirado em `seq 4` sobe mesmo com o item 2 esperando.

`resolved_uuids` também é semeado por qualquer uuid que o cliente já leu do servidor,
de modo que reinstalar o app não invalida dependências já satisfeitas.

**Onde a invariante mora:** no elegibilidade-check da drenagem, mais um índice
`by_state_and_seq` no object store. Reforço no servidor: a FK
`tasks.robot_id → robots.id` faz o item 2 falhar com 404/422 se a ordem for violada —
o banco é a rede de segurança, o grafo é o mecanismo.

**Alternativa descartada — enviar tudo em um único batch transacional.** Um endpoint
`POST /api/v1/sync` recebendo o lote inteiro resolveria a ordem no servidor, dentro de
uma transação. Descartado por três motivos: (a) exige um endpoint de escrita paralelo a
todos os endpoints REST, com policy própria, duplicando a matriz de autorização §4.1
que `authorization-policies` acabou de estabelecer; (b) falha atômica do lote significa
que uma tarefa com nome inválido descarta 40 avanços válidos; (c) o lote cresce sem teto
para quem passou o dia offline.

**Alternativa descartada — inferir dependência por prefixo de URL.** `POST
/robots/R/tasks` "obviamente" depende de `R`. Funciona até um `advance` cuja URL é
`/tasks/T/advances` e cuja dependência real é `T`, que por sua vez depende de `R`
transitivamente — a inferência precisaria reconstruir a hierarquia a partir de strings.
Declarar é uma linha no hook de mutation.

### D7-5 — Falha permanente cascateia como `blocked`, com decisão explícita do usuário

O cenário difícil: `robot.create R` falha em definitivo (422 — nome duplicado no
workspace) e há 5 mutations dependentes atrás.

1. `R` vai para `failed` (permanente).
2. O fechamento transitivo de dependentes de `R` vai para `blocked` — **não** `failed`,
   porque não falharam; ficaram órfãos.
3. A fila **continua drenando** todo item cujo fechamento de dependências não contém
   `R`. Este é o requisito de "não travar a fila para sempre".
4. O indicador de gravação entra em `bloqueado` e a UI oferece exatamente duas ações,
   nomeadas em pt-BR: **"Corrigir e reenviar"** (edita o body do item `failed`, ex.:
   renomeia o robô, e destrava a cascata) e **"Descartar 6 alterações"** (o item e todo
   o fechamento transitivo saem da fila e a sobreposição otimista correspondente é
   revertida, com a UI voltando à verdade do servidor).
5. Descarte é **sempre explícito**. Nunca automático, nunca por TTL.

Classificação de erro, que decide entre retry e falha permanente:

| Resposta | Classe | Ação |
|---|---|---|
| Erro de rede / `fetch` rejeitado | retryable | backoff, sem contar tentativa contra o teto |
| 408, 429, 500, 502, 503, 504 | retryable | backoff exponencial, conta tentativa |
| 401 | especial | pausa a fila inteira, dispara refresh (D4); retoma ou vai para login |
| 409 (`lock_version`) | conflito | item para `failed` com o estado do servidor no corpo; UI abre reconciliação (§2.4) |
| 403 | permanente | papel mudou (`view` agora, D6 revogação ao vivo). `failed`, sem retry |
| 404 | permanente | recurso removido por outra pessoa. `failed` |
| 422 | permanente | `failed` |
| 2xx | sucesso | `done`, uuid entra em `resolved_uuids` |

Backoff: `min(2^attempts × 1s, 5min)` com jitter de ±20%. Teto de **8** tentativas
retryable → quarentena (`failed`, classe "esgotado"). Sem o teto, um 500 permanente do
servidor gera um loop de reenvio que drena bateria no chão de fábrica.

**Onde a invariante mora:** máquina de estados do item na camada de drenagem, com teste
de tabela cobrindo cada linha acima. O 403 permanente é o par cliente da revogação ao
vivo de `realtime-collaboration`.

**Alternativa descartada — descartar automaticamente dependentes após N dias.** Perde
trabalho do usuário em silêncio. O produto é um registro de comissionamento; perder um
avanço sem avisar é a falha mais cara que existe aqui.

### D7-6 — Idempotência mora no uuid do recurso, não em um header

O uuid gerado no cliente (D1) **é** a chave de idempotência. O servidor faz
`INSERT ... ON CONFLICT (id) DO NOTHING RETURNING *` e responde `200` no replay
(D-H2, `commissioning-hierarchy`). Para avanços, o mesmo: mesmo uuid de avanço reenviado
→ um `task_advances`, e a máquina de estados §2.2 **não** é reaplicada.

Reforço de banco: PK `uuid` é índice único. Duas entregas do mesmo `advance.create A`
não conseguem produzir duas linhas nem que a aplicação queira.

**Alternativa descartada — header `Idempotency-Key` com tabela de chaves e TTL.**
É o padrão para POST sem id natural. Aqui o id **é** a chave, e um TTL cria a janela
exata que precisamos que não exista: o cliente que passou uma semana offline reenvia
depois da expiração da chave e duplica. Mesma conclusão de D-H2; registrada aqui porque
é aqui que o replay tardio de fato acontece.

**Consequência para PATCH/DELETE:** não são naturalmente idempotentes por uuid, mas são
idempotentes por semântica — `PUT` de conjunto de responsáveis (D-RT-6) e `DELETE` de um
uuid já removido responde 404, que classificamos como permanente e cujo efeito desejado
(o recurso não existe) já foi atingido. `DELETE` que devolve 404 é tratado como
**sucesso** para fins de fila, com um teste dedicado, porque tratá-lo como falha
encheria a quarentena de itens já satisfeitos.

### D7-7 — Sobreposição otimista é **derivada da fila**, e vence eventos ao vivo

O modo ingênuo — `queryClient.setQueryData` mutando o cache — quebra em cima de D6: um
evento do `WorkspaceChannel` invalida a query key, o refetch traz a verdade do servidor
(que ainda não tem a mutation pendente), e a UI **pisca de volta** o progresso de 60
para 50 na frente do engenheiro.

Modelo adotado: o cache do React Query guarda **só a verdade do servidor**. A
sobreposição é uma função pura `overlay(serverData, pendingMutations) → viewData`,
aplicada no `select` do hook de leitura, com a fila em Zustand como fonte reativa
(D9: Zustand para estado de cliente, e a fila é estado de cliente). Consequências:

- Refetch por invalidação não pisca: a sobreposição é reaplicada sobre o dado novo.
- Item vira `done` → sai da fila → a sobreposição desaparece exatamente no momento em
  que o dado do servidor já a contém.
- Item vira `failed`/descartado → a sobreposição desaparece e a UI volta à verdade do
  servidor. Reversão é a ausência da sobreposição, não um rollback manual.

Regra de precedência, explícita: **para uma entidade com mutation pendente, a
sobreposição sempre vence o dado do servidor**, inclusive dado recém-chegado por
evento ao vivo. A pessoa vê o próprio trabalho. Quando a mutation sai da fila, o
servidor volta a mandar.

**Onde a invariante mora:** função `overlay` pura e testável em isolamento, com um
teste que simula a sequência exata: enfileira `+10` → chega evento do canal → refetch
devolve progresso antigo → a view continua mostrando o valor otimista.

**Alternativa descartada — `onMutate`/`onError` do React Query com snapshot e rollback.**
É o padrão da biblioteca e funciona para mutation com ciclo de vida curto. Aqui a
mutation pode viver **horas** na fila, atravessando refetches, remounts, reloads da
página e trocas de aba. O snapshot em memória não sobrevive a nenhum dos quatro.

### D7-8 — `recorded_at` é carimbado no **enfileiramento** (D8)

`recorded_at = new Date().toISOString()` no instante em que o usuário confirma o modal,
gravado no item da fila, enviado no body. O servidor persiste `recorded_at` do cliente e
`created_at` próprio. Trilha e relatório exibem `recorded_at`.

Relógio do cliente é confiado com limite: o servidor rejeita `recorded_at` mais de **5
minutos no futuro** ou anterior a `created_at - 90 dias`, coerente com o teto de idade
da fila. Fora da janela, o servidor grava `created_at` e marca a divergência — regra
que **pertence a `progress-advances`**; citada aqui porque é aqui que a violação nasce
(celular com relógio errado no galpão).

### D7-9 — Drain disparado por eventos do app; sem Background Sync

Gatilhos: evento `online`, `visibilitychange` para visível, foco da janela, sucesso de
qualquer requisição (sinal de que a rede voltou), e um timer de 30s enquanto houver
item `pending`. Um `HEAD /api/v1/health` decide se vale tentar, para não gastar bateria
disparando 40 requisições contra uma rede morta.

**Alternativa descartada — Background Sync API.** Drenaria com o app fechado, o que
seria genuinamente melhor. Não adotada: iOS Safari não a implementa, e o parque é
majoritariamente celular no galpão. A fila precisaria existir de qualquer forma como
fallback, e manter dois caminhos de drenagem dobra a superfície do bug mais caro da
capacidade. Reavaliável quando a cobertura mudar — o ponto de extensão é o gatilho, não
a fila.

**`navigator.onLine` não é fonte de verdade.** É `true` em qualquer Wi-Fi de galpão sem
rota de saída. Usado só como dica para *disparar*; o estado real de conectividade vem
do resultado das requisições.

### D7-10 — Uma aba drena, todas veem: Web Locks + `BroadcastChannel`

Sem coordenação, três abas abertas drenam a mesma fila em paralelo. Idempotência (D7-6)
evita duplicata, mas não evita 3× o tráfego, nem a corrida em que duas abas avançam
`attempts` do mesmo item e estouram o teto de 8 com 3 tentativas reais.

- **Eleição de líder:** `navigator.locks.request('robotrack-queue-drain', {mode:
  'exclusive'})`. Quem segura o lock drena. O lock é liberado pelo browser ao fechar a
  aba, sem heartbeat e sem lock órfão.
- **Fan-out:** o líder publica em `BroadcastChannel('robotrack-queue')` a cada transição
  (`enqueued`, `inflight`, `done`, `failed`, `blocked`). Toda aba atualiza o store da
  fila e, por consequência, a sobreposição e o indicador de gravação.
- **Fallback:** sem `navigator.locks` (Safari < 15.4), o líder é eleito por um registro
  `leader` em IndexedDB com `expires_at` renovado a cada 5s; entrada expirada é tomada.
  Sem `BroadcastChannel`, o polling de 30s do IndexedDB mantém as abas coerentes — pior,
  porém correto.

**Onde a invariante mora:** o lock nomeado é a garantia; toda escrita de `attempts`
acontece dentro de uma transação `readwrite` do IndexedDB, então mesmo o caminho de
fallback não perde contagem.

**Alternativa descartada — `SharedWorker` como dono da fila.** Modelo mais limpo, uma
instância por origem. Descartado por não ser suportado em Safari no iOS, que é
exatamente a plataforma do usuário no chão de fábrica.

### D7-11 — `safeStorage` e três níveis de degradação

**Nenhum** acesso a `localStorage`/`sessionStorage`/`indexedDB` no app é direto. Tudo
passa por `safeStorage`, que envolve cada chamada em `try/catch` e devolve `null` em
falha. Isso mata a classe de bug que trava o login em modo privado: no Safari privado
antigo, `localStorage.setItem` **lança** `QuotaExceededError`, e um throw não capturado
no boot do store de auth deixa a tela branca. Travar o login por causa de um bloqueador
é o pior modo de falha possível para alguém de luva num galpão.

Sonda no boot (escreve e lê de volta uma chave sentinela em cada meio) classifica:

| Nível | Condição | Comportamento |
|---|---|---|
| `persistent` | `localStorage` + IndexedDB OK | Tudo ligado |
| `session-only` | `sessionStorage` OK, `localStorage` bloqueado | Sessão morre ao fechar a aba; fila em memória (perdida no reload, avisada); tema não persiste |
| `memory-only` | Tudo bloqueado | Adapter em memória. Login **funciona**. Fila offline **desligada** |

Em `session-only` e `memory-only` um aviso persistente e dispensável-por-sessão diz, em
pt-BR: *"Seu navegador está bloqueando o armazenamento. Você pode usar o RoboTrack
normalmente, mas a sessão não vai persistir ao fechar" —* e, em `memory-only`,
adicionalmente *"e alterações feitas sem conexão não serão salvas."*

Em `memory-only` a fila é **desligada, não degradada**: mutations vão direto à rede e
falham visivelmente se offline. Manter uma fila que não sobrevive a um reload seria
prometer durabilidade sem lastro — que é justamente a desonestidade de estado que o
PRODUCT.md proíbe.

**Onde a invariante mora:** ESLint `no-restricted-globals` para `localStorage`,
`sessionStorage` e `indexedDB` fora de `lib/storage/safeStorage.ts`, falhando o CI. Uma
convenção documentada seria reintroduzida no primeiro store novo.

### D7-12 — Teto: 500 itens ou 5 MB, rejeição na entrada

Ao atingir o teto, novas mutations são **rejeitadas** com um erro visível ("Fila offline
cheia — conecte-se para sincronizar"), e a fila existente é preservada. Descartar o item
mais antigo para caber o novo (política de janela deslizante) descartaria silenciosamente
o avanço registrado às 14h.

Itens `done` são podados imediatamente; `failed` sobrevivem até decisão do usuário e
contam para o teto — de propósito, porque uma quarentena crescendo sem limite é um
problema que precisa ser visto.

## Risks / Trade-offs

| Risco | Mitigação |
|---|---|
| Network-first custa uma ida à rede em todo asset, mesmo online | Assets do Vite são content-hashed e servidos com `immutable` pelo CDN — o *HTTP cache* absorve; o SW só entra quando a rede falha. §4.3 é explícita e não negociável |
| `depends_on` declarado errado por um hook novo → 404 de FK e item na quarentena | Helper `enqueueMutation` que **exige** `depends_on` (tipo sem default); teste E2E do cenário canônico; a FK do banco é a rede de segurança |
| Sobreposição otimista mascarando um servidor que rejeita há horas | O indicador de gravação nunca diz "salvo" enquanto houver item na fila; `pendente`/`bloqueado` são estados de primeira classe |
| Fila com esquema versionado migrando entre deploys | `onupgradeneeded` com número de versão; itens de versão desconhecida vão para `failed` classe "incompatível", nunca são descartados |
| Reconciliação 409 em massa depois de um dia offline | Um 409 por vez, na ordem, na UI de §2.4. Reconciliação em lote fica fora do escopo e está em Perguntas em aberto |
| `memory-only` sem fila frustra quem usa modo privado no galpão | Trade-off consciente: falha visível > durabilidade falsa |

## Plano de migração

Não há dado a migrar — não existe fila anterior. Há **dívida de template** a converter:

1. `lib/api/client.ts` e os stores Zustand (`authStore`, `themeStore`) hoje tocam
   `localStorage` direto. Convertidos para `safeStorage` **antes** de qualquer código de
   fila, senão a sonda de armazenamento não cobre o caminho de boot que trava.
2. `app-shell-navigation` já move o token para fonte única no store de auth. Esta
   capacidade **depende** disso e não o refaz.
3. Rollout do SW: o legado registrava `sw.js` na raiz. Se o mesmo host servir o app
   novo, um SW antigo pode estar instalado no dispositivo. O novo `install` **MUST**
   apagar todo cache com prefixo `robotrack-v9-` (nome do legado) além dos próprios
   antigos. Sem isso, um dispositivo com o app legado instalado serve o `index.html`
   antigo do cache e nunca vê o app novo — falha silenciosa e não reportável, porque o
   usuário não sabe que está vendo a versão errada.
4. Ordem obrigatória: `safeStorage` → SW → fila → sobreposição → coordenação entre abas.
   Cada uma é testável isolada, e a fila sem `safeStorage` reintroduz o travamento.

## Perguntas em aberto

1. **Teto de idade da fila.** Um item `pending` de 90 dias ainda deve subir? Proposta:
   sim, mas com aviso na UI acima de 7 dias — cruza com a janela de `recorded_at` de
   D7-8. Precisa de acordo com `progress-advances`.
2. **Reconciliação de 409 em lote.** Se 30 avanços conflitam de uma vez, a UI de §2.4
   um-a-um é sofrível. Fora do escopo desta onda; anotado como dívida.
3. **Persistir o cache de leitura do React Query em IndexedDB** para navegação offline
   mais rica. Atraente, mas precisa de política de descarte na troca de workspace tão
   rigorosa quanto a de `app-shell-navigation`, sob pena de vazar dado entre tenants no
   dispositivo. Deliberadamente adiado.
4. **Telemetria de fila** (profundidade, taxa de quarentena, idade do item mais antigo)
   — depende de `delivery-and-observability` decidir o transporte de métricas do cliente.

## O que ficou de fora (por limite de tamanho)

Priorizado para caber em 35 tarefas — acima do alvo de 30, e conscientemente: a
capacidade é a ponta do caminho crítico e absorve quatro comportamentos que o Firestore
dava de graça. Coberto: o cenário canônico (criar robô + avanço offline),
idempotência, poison/cascata, SW, storage bloqueado e coordenação entre abas. **Fora**:
persistência do cache de leitura (aberta nº 3), reconciliação de 409 em lote (aberta
nº 2), Background Sync (D7-9) e telemetria (aberta nº 4).
