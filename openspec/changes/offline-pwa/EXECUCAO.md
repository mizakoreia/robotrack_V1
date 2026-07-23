# EXECUCAO — offline-pwa (Onda D7)

Mapa de execução. Escrito ANTES de qualquer código (commit G0). RETOMADA no fim.

## Ponto de partida

A MAIOR lacuna do porte e a ponta do caminho crítico. O Firestore dava de graça
quatro coisas (cache write-through, fila de mutations, resolução de conflito,
coordenação entre abas); aqui cada uma vira artefato de primeira classe. Depende
de `robot-task-table` (COMPLETA), consome o handoff de `realtime-collaboration`
(D6, COMPLETA — o gate de represamento já espera o contrato `hasPendingFor`) e
destrava a honestidade temporal (D8) que o relatório assinado promete.

## RECONCILIAÇÃO COM A REALIDADE (crítico — ler antes de codar)

- **`safeStorage` JÁ EXISTE** em `src/lib/safeStorage.ts` (NÃO em `lib/storage/`
  como 1.1 pede): tem `get/set/remove` por `kind` ('local'|'session'), fallback em
  `Map` de memória, `set` devolvendo `true` (real) / `false` (memória), e
  `withStorageTimeout`. FALTA: a classificação em NÍVEL (`persistent` /
  `session-only` / `memory-only`) e a sonda de boot. **Decisão:** ESTENDER o
  arquivo existente (adicionar `probeStorageLevel()` + o nível), NÃO relocar —
  sete arquivos já importam de `lib/safeStorage` (`themeStore`, `authStore`,
  `oauthState`, `invite`, `InviteRoute`, `AppearancePanel`, `client.ts`). 1.1 vira
  "adicionar níveis ao safeStorage existente"; registrar a divergência de caminho.
- **1.2 é PARCIAL:** o `safeStorage` existe mas nem todo acesso passa por ele —
  `themeStore`/`workspaceStore` (persist do zustand), `AppearancePanel` (probe
  próprio), `InviteRoute` ainda tocam `localStorage`/`sessionStorage` direto.
  Auditar os 7 arquivos, rotear tudo pelo `safeStorage`, e ligar
  `no-restricted-globals` para os três globais fora de `lib/`. O `themeStore` usa
  `zustand/middleware persist` → precisa de um storage adapter sobre `safeStorage`.
- **Service worker: NÃO EXISTE.** Sem `public/sw.js`, sem workbox, sem
  vite-plugin-pwa. Construir do zero (grupo 2). O `CACHE_NAME = hash do build` sai
  de um plugin do Vite (2.4). Purga do prefixo legado `robotrack-v9-` (o PWA
  Firebase antigo). `Cache-Control: no-cache` para `/sw.js` é caveat de
  `delivery-and-observability` (registrar handoff).
- **IndexedDB: NADA.** Sem `idb`, sem `fake-indexeddb`. O guard `no-heavy-deps`
  (design-system) barra recharts/tiptap/slate/radix/CVA — **NÃO** barra `idb`
  (~1KB) nem `fake-indexeddb` (dev). Adicionar os dois; `idb` deixa o esquema
  versionado e as transações `readwrite` (6.2) legíveis. Se preferir zero-dep,
  IndexedDB cru é possível mas verboso — decidir no G3 (preferir `idb`).
- **D1 (uuid cliente) JÁ ESTÁ:** `useHierarchy` cria com `id ?? newId()`
  (project/cell/robot), advances e lote de robôs geram uuid. O grafo de dependência
  (D7-4) é exprimível — criar robô offline PRODUZ id, então dá para enfileirar uma
  tarefa contra ele. Auditar se algum caminho de create ainda nasce sem uuid.
- **Otimista HOJE é `setQueryData` em `useHierarchy`** (`optimisticProject` etc.);
  o avanço (`robot-task-table`) NÃO tem otimista. O overlay de 7.1/7.2 é
  DERIVADO DA FILA (`overlay(serverData, pending)`), "sem setQueryData otimista":
  reconciliar — o setQueryData do `useHierarchy` sai e vira overlay no `select`,
  senão duas fontes de otimismo brigam. Precedência sobre refetch E sobre evento do
  `WorkspaceChannel` (o gate de D6 já REPRESA a invalidação enquanto há mutação em
  voo; o overlay cobre o resto: item ainda enfileirado, não em voo).
- **Handoff de D6 pronto:** `Realtime`'s `OfflinePendingProbe`
  (`invalidationGate.ts`) é consumido como `NO_OFFLINE_PENDING` (stub vazio). 7.3
  liga a fila real: `hasPendingFor(kind, id)` lê o store da fila. É o ponto de
  encontro D6×D7 — o gate represa por mutação EM VOO (React Query) E por item na
  fila offline (este contrato).
- **Indicador de gravação:** `persistenceStore`/`SaveIndicator` têm
  `SaveState = 'saving'|'saved'|'error'`. 7.3 ACRESCENTA `pendente` e `bloqueado`
  (estender a união nos dois arquivos + o `MAP` de ícones/texto do SaveIndicator).
- **`HEAD /api/v1/health`: NÃO EXISTE.** A sonda de drenagem (4.3) precisa dele —
  adicionar um endpoint leve (sem tenant, sem auth pesada) no backend; é a única
  peça de servidor desta onda. Registrar em `api/root.rb` PUBLIC/TENANT_EXEMPT.
- **E2E Playwright (4.4, 6.3, 8.5, 8.6):** o padrão do repo é integração
  RTL/`fake-indexeddb` (o harness Playwright de `quality-and-accessibility` NÃO
  existe — mesma divergência de `realtime-collaboration` 7.5/9.2). Multi-contexto
  (6.3) e WebKit (8.6) SÃO Playwright puro → registrar como HANDOFF para
  `quality-and-accessibility`; entregar aqui a versão integração (duas instâncias
  compartilhando um `fake-indexeddb`, contando chamadas por um axios mockado).

## Ordem dos grupos (mapa)

| Grupo | Escopo | Tarefas |
|---|---|---|
| **G1** | Fundação de storage: níveis no `safeStorage` existente (`persistent`/`session-only`/`memory-only`) + sonda de boot; rotear os 7 consumidores; `no-restricted-globals`; aviso persistente D7-11; teste dos 3 níveis | 1.1–1.4 |
| **G2** | Service worker: `public/sw.js` (install/skipWaiting/activate+purga `robotrack-v9-`/claim), guard de não-interceptação (allowlist `^/(api\|auth\|cable\|rails/active_storage)/`, não-GET, cross-origin), network-first same-origin, fallback SPA; plugin Vite do `CACHE_NAME`; registro + aviso `controllerchange`; suíte de `FetchEvent` sintéticos | 2.1–2.5 |
| **G3** | Fila — esquema: IndexedDB `robotrack` store `mutations` (`keyPath id`, `seq` autoinc, índices `by_state_and_seq`/`by_workspace`), `resolved_uuids`, `onupgradeneeded` com quarentena; `enqueueMutation` (`depends_on` obrigatório no tipo, `recorded_at` no enfileiramento/D8); teto 500/5MB; store Zustand projeção reativa escopada por `workspace_id`; teste `fake-indexeddb` | 3.1–3.4 |
| **G4** | Fila — grafo + drenagem: elegibilidade por `depends_on`×`resolved_uuids` (pula não-elegível sem bloquear), povoar `resolved_uuids` de 2xx + uuids do servidor, laço sequencial por `seq` (1 em voo), gatilhos filtrados por sonda `HEAD /api/v1/health` (+ endpoint no backend); E2E canônico robô→tarefa→avanço | 4.1–4.4 |
| **G5** | Fila — idempotência/erro/poison: classificação retryable/permanente/conflito/auth (D7-5, DELETE 404 = sucesso), backoff `min(2^n×1s,5min)`±20% jitter teto 8, pausa global em 401 sem consumir tentativa, cascata `blocked` (fechamento transitivo), UI de reconciliação ("Corrigir e reenviar"/"Descartar N"), 409 de `lock_version` sem reenvio; teste de tabela + replay duplicado | 5.1–5.5 |
| **G6** | Coordenação entre abas: líder por `navigator.locks` em volta da drenagem, fan-out por `BroadcastChannel` + hidratação nas não-líderes, fallback (registro `leader` em IndexedDB, `expires_at` 5s, polling 30s), `attempts` sempre em `readwrite`; teste multi-contexto (integração; WebKit→handoff q&a) | 6.1–6.3 |
| **G7** | Overlay + indicador: `overlay(serverData, pending)` puro (robô/tarefa/avanço), ligado ao `select` de `robot-task-table`/`hierarchy-screens` com precedência sobre refetch e evento do canal (e SAÍDA do `setQueryData` do `useHierarchy`), `hasPendingFor` no gate de D6, indicador `pendente`/`bloqueado` (+ desligar fila em `memory-only`); teste da sequência anti-flicker | 7.1–7.4 |
| **G8** | Sessão/convite/entrega: meio de storage da sessão × "manter conectado" × nível, tema antes da 1ª pintura; token de convite em `sessionStorage`/`safeStorage`; export da fila (ANTES de 8.4); migração de esquema versionada; E2E honestidade temporal (14:03 na trilha, `created_at` 17:41) + deploy; suíte Chromium+WebKit (handoff harness) | 8.1–8.6 |

## Armadilhas previstas

- **`persist` do zustand × safeStorage:** `themeStore`/`workspaceStore` usam o
  middleware `persist` com `localStorage` default. Trocar por um `StateStorage`
  adapter sobre `safeStorage` — senão `memory-only` volta a lançar no boot.
- **SW interceptando `/cable`:** o WebSocket do D6 NÃO pode passar por
  `respondWith`. A allowlist inclui `cable` — e o handshake é `GET` com `Upgrade`,
  então o guard de não-GET não basta; a allowlist de rota é o que salva (D7-1).
- **Overlay × gate de D6:** o gate represa invalidação por mutação EM VOO (React
  Query); o overlay cobre item ENFILEIRADO/bloqueado (fila). Os dois juntos = zero
  flicker; testar a sequência enfileirar→evento→refetch (7.4) SEM snapshot em
  memória (o remount o destruiria — é a armadilha que a tarefa nomeia).
- **`recorded_at` no enfileiramento, não no envio (D8):** carimbar no instante do
  modal. O `created_at` do servidor é o do envio (17:41); a trilha mostra o
  `recorded_at` (14:03). Já existe `recorded_at` no `useRecordAdvance` — a fila
  passa a ser a dona do carimbo.
- **Poison message:** classificação errada dá laço infinito (bateria) ou
  quarentena cedo demais (perde escrita). A tabela D7-5 é lei; DELETE 404 = sucesso
  (reenvio de exclusão já aplicada), 403 de revogação → `failed` direto.
- **`fake-indexeddb` e transações:** o teste de `attempts` em `readwrite` (6.2)
  precisa do adapter real de transação; `fake-indexeddb` cobre, mas a disputa de
  liderança entre abas exige duas instâncias sobre o MESMO backing store.
- **Endpoint `/health`:** sem tenant e barato; a sonda é `HEAD`. Cair na allowlist
  pública E na isenção de tenant de `api/root.rb`, senão a sonda 401/400.

## Baseline

Frontend 402/0; tsc limpo (fechamento de `realtime-collaboration` G9). Backend
verde. Sem service worker, sem IndexedDB, sem fila — tudo desta onda nasce aqui.

## RETOMADA

Ler este arquivo + design.md (D7-1…D7-12). Estado por grupo em tasks.md (`- [x]`).
Protocolo por grupo: aplicar → specs/integração dirigidos 0 falhas + `tsc` limpo →
marcar tasks → `npx --yes @fission-ai/openspec@1.6.0 validate offline-pwa
--strict` → UM commit `G<n>:` → fast-forward `main` + push → resumo pt-BR
client-friendly → pedir autorização. `idb`+`fake-indexeddb` entram no G3. O
endpoint `/health` entra no G4 (única peça de backend). NUNCA duas suítes
simultâneas.
