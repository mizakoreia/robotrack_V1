# Proposta — `app-shell-navigation`

## Why

A ESPECIFICACAO.md **§3.10** e a seção **"Navegação e IA"** do `DESIGN.md` descrevem a
moldura permanente do RoboTrack: a sidebar de três destinos, o rodapé com indicador de
gravação e card de usuário, a barra de topo com contexto de workspace à esquerda e
gatilho de conta à direita, e os menus suspensos. Nada disso é decoração — é o único
lugar do produto onde o usuário descobre **em qual workspace está**, **com que papel**,
e **se o que ele acabou de digitar chegou ao servidor**.

Três coisas tornam esta capacidade estruturalmente urgente, e não cosmética:

1. **§3.10 tem um requisito de segurança disfarçado de UX.** "Trocar de workspace
   descarta o estado anterior por completo (não pode vazar dados entre workspaces)."
   No legado o Firestore desmontava os `onSnapshot` e a tela ia junto. No alvo, o
   React Query mantém um cache em memória que **sobrevive à navegação**. Um servidor
   com RLS perfeita (D2) e policies perfeitas (D3) ainda exibe robôs do workspace A
   dentro do workspace B se o cliente renderizar cache quente enquanto refaz o fetch.
   O vazamento entre tenants aparece no cliente. Ninguém mais no grafo cobre isso.

2. **D9 é desta capacidade, e é bloqueante para seis telas.** O template tem React
   Query configurado em `frontend/src/main.tsx` e usado em **uma** página; o padrão de
   fato é `useEffect` + `apiClient` + `useState`. Não existe convenção de query key.
   `hierarchy-screens`, `robot-task-table`, `my-tasks-view`, `commissioning-report`,
   `workspace-settings` e `realtime-collaboration` (que precisa saber **qual key
   invalidar** ao receber um evento do `WorkspaceChannel`, D6) todas dependem de uma
   convenção que hoje não existe. Se ela não for escrita como requisito antes da
   Onda 7, seis capacidades inventam seis convenções e D6 fica sem alvo.

3. **O token vive em dois lugares.** `lib/api/client.ts` lê
   `localStorage.getItem('access_token') || localStorage.getItem('token')`; o
   `authStore` do Zustand persiste o mesmo token em `auth-storage`. Os dois são
   sincronizados à mão. Duas fontes de verdade para credencial é como se produz um
   logout que não desloga.

Esta capacidade está na **Onda 2** e depende de `design-system` (tokens, escala de
z-index semântica, `Save indicator`, `Badge`) e de `identity-and-auth` (sessão, usuário
corrente, logout). Ela é consumida por toda a Onda 7 em diante.

**O que se traduz de Firebase:** o descarte de estado que o `onSnapshot` dava de graça
ao ser desmontado vira **descarte explícito do cache do React Query**; a leitura do
workspace corrente, que no legado era um caminho de documento embutido em cada query,
vira o **primeiro segmento da query key** (`['ws', wsId, …]`).

## What Changes

**Casca da aplicação**
- Rota-layout `AppShell` com sidebar fixa, topbar e área de conteúdo rolável própria
  (`overflow-y: auto`), envolvendo as rotas autenticadas hoje declaradas inline em
  `frontend/src/app/App.tsx`.
- **Sidebar** com exatamente três destinos: Visão Geral (`/`), Minhas Tarefas
  (`/minhas-tarefas`), Relatório (`/relatorio`). Estado ativo por **preenchimento
  tintado + ícone em `--accent`** — **nunca** faixa lateral. Nenhum item de
  configuração entra na sidebar.
- **Rodapé da sidebar**: indicador de gravação + card de usuário (nome sobre e-mail)
  que abre o menu **"Edição e visualização"** com três itens: tarefas/equipe/filtros,
  logs & histórico, backup. Os destinos desses itens pertencem a `workspace-settings` e
  `audit-log`; aqui entra só o gatilho e a rota.
- **Topbar**: contexto do workspace à esquerda (seletor + badge de papel), gatilho da
  conta à direita abrindo adicionar usuário, alternar tema, sair.
- **Colapso mobile**: abaixo de 768px a sidebar vira gaveta sobreposta; o rodapé e o
  indicador de gravação continuam alcançáveis.

**Menus suspensos (portal)**
- Todo menu suspenso é renderizado como **filho direto da raiz do documento** via
  `createPortal`, com `position: fixed` e coordenadas de viewport calculadas a partir
  do `getBoundingClientRect()` do gatilho. Deliberado: `absolute` dentro da área
  rolável seria recortado.
- **Medição antes de abrir** para decidir se o menu sobe ou desce, e para escolher o
  alinhamento horizontal quando ele estouraria a borda direita.
- Fecha em: clique fora, `Esc` (**devolvendo o foco ao gatilho**), rolagem do conteúdo,
  redimensionamento da janela, escolha de item. Navegação por setas, `Home`/`End`.

**Contexto e troca de workspace (§3.10)**
- Seletor de workspace que **só aparece com mais de um**; com exatamente um, o nome do
  workspace é texto estático sem affordance de clique.
- Badge de papel: **Dono / Editor / Somente leitura**, rotulado sempre, como badge
  (rótulo) e nunca como select (controle).
- **Troca descarta o estado anterior por completo**: `queryClient.clear()` — cache
  inteiro, não invalidação seletiva — mais reset das fatias de UI por workspace do
  Zustand, antes de qualquer render do novo workspace.

**D9 — React Query como padrão único de estado de servidor**
- Convenção de query key com `['ws', wsId, …]` obrigatório em toda query de domínio,
  com um **guard em desenvolvimento e em teste que falha** se uma query de domínio for
  registrada fora dessa forma.
- Localização canônica dos hooks (`features/<dominio>/api/`), política de `staleTime` e
  de invalidação, e a fronteira do Zustand: **só estado de cliente** (tema, filtros de
  UI, fila offline, estado do shell).
- **BREAKING** — o padrão `useEffect + apiClient + useState` deixa de ser aceitável para
  leitura de domínio. A página do template que usa React Query é realinhada à convenção
  e as demais leituras de domínio existentes são migradas ou removidas junto com
  `seal-template-baseline`.

**Dívida do token**
- **BREAKING** — o token deixa de ser lido de `localStorage` dentro do `apiClient`. A
  única fonte de verdade passa a ser o store persistido de auth, exposto ao `apiClient`
  por injeção de acessor no boot (sem ciclo de import). Migração única lê as chaves
  legadas `access_token` / `token`, hidrata o store e as **remove**.

**Contrato do indicador de gravação**
- Estados `salvando` / `salvo` / `erro`, derivados de um store de persistência com
  contador de mutations em voo e profundidade de fila. `offline-pwa` (D7) é o produtor:
  o contrato de escrita fica definido **agora**, para que a Onda 9 se ligue nele sem
  redesenhar o indicador.

### Não-objetivos

- **Conteúdo de qualquer tela.** Visão Geral, Minhas Tarefas e Relatório são
  `hierarchy-screens`, `my-tasks-view` e `commissioning-report`. Aqui só existe a rota,
  o destino da sidebar e o outlet.
- **Painel de equipe, convites e revogação em tempo real** (§3.10, resto) —
  `workspace-invitations` e `realtime-collaboration`. Esta capacidade fornece o gatilho
  "adicionar usuário" e o ponto de montagem; não o fluxo.
- **Modelo de Workspace/Membership/papel no servidor e RLS** — `workspace-tenancy`
  (D2, D10). Aqui só se consome o índice de workspaces do usuário, que é **cache de UI e
  nunca fonte de autorização** (invariante §4.1 nº 2).
- **Autorização efetiva** — `authorization-policies` (D3). Esconder um item de menu para
  `view` é conveniência; o servidor nega de qualquer forma (invariante §4.1 nº 1).
- **Tokens, primitivos visuais e a escala de z-index** — `design-system`. Consumidos,
  não definidos.
- **Service worker, IndexedDB e a fila offline** — `offline-pwa`. Definimos apenas o
  contrato que o indicador consome.
- **Login, cadastro e o protocolo de refresh** — `identity-and-auth` (D4). Mexemos só
  em **onde o token mora no cliente**.
- **Alternância de tema em si** — `workspace-settings` / `design-system`. A topbar
  apenas expõe o gatilho.
- **Auditoria de a11y medida** — `quality-and-accessibility`. Aqui há requisitos de
  foco e ARIA; a medição formal é lá.

## Capabilities

### New Capabilities

- `app-shell-navigation`: casca persistente — sidebar de três destinos com estado ativo
  por preenchimento, rodapé com indicador de gravação e card de usuário, topbar, menus
  suspensos em portal com medição prévia e fechamento por clique fora / `Esc` /
  rolagem / resize, e o contrato do indicador de gravação.
- `workspace-context-switching`: seletor de workspace condicional, badge de papel, e o
  descarte total de estado na troca — a barreira de vazamento entre tenants no cliente.
- `client-server-state-conventions`: D9 — convenção de query key, localização dos hooks,
  política de `staleTime`/invalidação, fronteira do Zustand, guard de forma de key, e
  fonte única de verdade para o token.

### Modified Capabilities

Nenhuma. `openspec/specs/` está vazio: nada foi construído ainda.

### Impact

**Código tocado**
- `frontend/src/app/App.tsx` — rotas passam a pendurar em um layout; deixa de ser lista
  plana.
- `frontend/src/main.tsx` — `QueryClient` sai daqui para um módulo próprio com defaults
  da convenção e é acessível ao handler de troca de workspace.
- `frontend/src/lib/api/client.ts` — **BREAKING**: acessor de token injetado; leitura
  direta de `localStorage` removida.
- `frontend/src/store/authStore.ts` — vira a fonte única do token; o resíduo de
  magic-login (`loginMethod`, `loginCode`, `devCode`) sai com D4 / `identity-and-auth`.
- Novos: `app/AppShell.tsx`, `components/menu/` (portal + posicionamento),
  `store/workspaceStore.ts`, `store/persistenceStore.ts`, `lib/query/`.

**Dependências de entrega**
- Nenhuma env var, fila ou adapter novo. Depende do endpoint de índice de workspaces do
  usuário, entregue por `workspace-tenancy`.
- O guard de forma de query key roda em teste e falha o CI — ver
  `delivery-and-observability` para o gate.

**Risco**
- Alto se atrasar: seis capacidades de tela ficam sem convenção de estado de servidor.
- O descarte de cache é a única barreira **cliente** contra vazamento entre tenants; um
  teste de regressão dele é obrigatório, não opcional.
