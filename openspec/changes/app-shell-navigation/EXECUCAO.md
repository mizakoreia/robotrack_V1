# EXECUCAO — app-shell-navigation

Mapa de execução. Escrito ANTES de qualquer código (commit G0). RETOMADA no fim.
Decisões próprias e armadilhas registradas à medida que aparecem.

## Ponto de partida

Branch empilhada sobre `design-system` (que fechou). Onda 2. Frontend-only.
Depende de `design-system` (tokens, z-index, SaveIndicator, Badge — TODOS prontos)
e de `identity-and-auth` (sessão, authStore, logout — prontos). Consumida por toda
a Onda 7+ (as telas). Baseline: backend 933/0/9pending; frontend 160/0; tsc/build limpos.

## Objetivo central

A moldura permanente (sidebar 3 destinos, rodapé com indicador de gravação + card
de usuário, topbar com contexto de workspace, menus em portal) E as convenções que
DESBLOQUEIAM seis telas: D9 (React Query como padrão único, key `['ws', wsId, …]`
com guard), a barreira CLIENTE contra vazamento entre tenants (`queryClient.clear()`
na troca), o contrato do indicador de gravação (produtor futuro = offline-pwa), e a
fonte única do token.

## RECONCILIAÇÃO COM A REALIDADE (crítico — várias tarefas já estão feitas)

O `proposal.md` descreve o estado do TEMPLATE; ondas anteriores já resolveram parte:
- **Token single-source (Grupo 2 / D-E): JÁ FEITO** por identity-and-auth. `client.ts`
  lê o token do `authStore` ("Fonte ÚNICA do token: o authStore, nunca localStorage
  direto (D4.9)"), não de `localStorage`. → Grupo 2 vira VERIFICAR + a migração das
  chaves legadas (`access_token`/`token`) + o sweep, se ainda faltarem.
- **QueryClient extraído (1.1): JÁ FEITO** — `lib/queryClient.ts` existe (usado por
  main.tsx, client.ts, accessRevoked). MAS os defaults estão no padrão do template
  (`staleTime` 5min). → 1.1 vira ALINHAR os defaults (30s/gcTime 5min/mutation retry 0).
- **workspaceStore (5.1): JÁ EXISTE** (`currentWorkspaceId`, `currentRoleLabel`,
  `workspaces`, `setWorkspaces`). → 5.1 vira ESTENDER (switchWorkspace + seletor único).
- **createPortal já usado em `components/ui/Modal.tsx`** (design-system). O guard de
  6.4 ("createPortal só em components/menu/") precisa ISENTAR o Modal (dialog é uso
  legítimo de portal). Decisão 1.
- **Keys `['ws', wsId, …]` já existem** em `advanceKeys/catalogKeys/hierarchyKeys`
  (changes done). A factory de 1.2 deve ser a canônica; as existentes ou consomem a
  factory ou o guard as tolera. Decisão 2.

## Ordem dos grupos

| Grupo | Escopo | Tarefas |
|---|---|---|
| **G1** | Fundação D9: alinhar defaults do QueryClient, factory tipada de keys (`lib/query/keys.ts`), guard de forma de key (DEV/test lança), testes | 1.1–1.4 |
| **G2** | Dívida do token: verificar single-source (já feito), migração das chaves legadas + remoção, logout→clear, sweep de `localStorage` no client | 2.1–2.4 |
| **G3** | Primitivo de menu em portal: `#rt-overlays`, `<PortalMenu>` (fixed, z-dropdown), medição prévia, 5 gatilhos de fechamento (+ teclado virtual), teclado, testes | 3.1–3.6 |
| **G4** | Casca: `AppShell` (rotas-filhas), sidebar (3 destinos, ativo por preenchimento), rodapé (card usuário + menu), topbar (slots + menu da conta), gaveta mobile, testes | 4.1–4.6 |
| **G5** | Contexto e troca: workspaceStore estendido, seletor condicional, badge de papel, `switchWorkspace()` (clear = barreira de vazamento), 403/ausência/degradação, testes de vazamento | 5.1–5.9 |
| **G6** | Persistência + convenção: `persistenceStore` (inFlight/queued/failed), indicador como projeção pura, migração da leitura do template, sweep de convenção D9 | 6.1–6.4 |

## Decisões de desenho já fixadas (do design.md — não reabrir)

- **D-A** — troca de workspace usa `queryClient.clear()` (cache INTEIRO), não `invalidateQueries`
  (renderizaria o dado antigo enquanto refaz o fetch = vazamento). Ordem: fechar overlays →
  `cancelQueries` → `clear` → resetar UI por ws → gravar wsId → navegar `/`.
- **D-B (D9)** — key `['ws', wsId, …]` obrigatória; factory tipada exige `wsId`; guard falha em
  DEV/test, reporta em prod. Hooks em `features/<dominio>/api/`; Zustand só estado de cliente.
- **D-C** — menus em portal na raiz (`createPortal`, fixed, z-dropdown), medição prévia com
  `visibility: hidden` (nunca display:none); fecha por clique-fora/Esc(devolve foco)/scroll/resize/
  escolha; teclado virtual só fecha se largura muda ou altura varia >120px.
- **D-D** — indicador de gravação: projeção pura de `persistenceStore` (inFlight/queued/failed),
  precedência `erro > salvando > salvo`, sem expiração. offline-pwa é o produtor futuro.
- **D-E** — token fonte única (authStore); acessor injetado no client (sem ciclo de import).
- **D-F** — sidebar só destinos; configuração no rodapé. **D-G** — papel é badge (rótulo), workspace
  é select (controle); nunca se parecem. **D-H** — índice de workspaces é cache de UI, NUNCA fonte
  de autorização (o servidor nega de qualquer forma).

## Decisões que EU tomo aqui (LER)

1. **Guard de portal (6.4) isenta `components/ui/Modal.tsx`.** O Modal do design-system usa
   `createPortal` legitimamente (dialog). O guard "createPortal só em components/menu/" ganha uma
   allowlist com o Modal — documentada, não silenciosa.
2. **Factory de keys canônica + keys existentes.** `lib/query/keys.ts` é a fonte. As três keys
   existentes (`advanceKeys/catalogKeys/hierarchyKeys`) JÁ têm a forma `['ws', wsId, …]`, então o
   guard as aceita. NÃO as reescrevo agora (mexeria em 3 changes done); a factory é para as telas
   NOVAS. Se sobrar tempo, unifico. Registro.
3. **Defaults do QueryClient no `lib/queryClient.ts` existente** (não crio `lib/query/client.ts`
   novo e duplicado). Alinho `staleTime` 5min→30s, adiciono `gcTime` 5min e `mutations.retry 0`.
   Path real do repo, divergência do texto registrada.
4. **Índice de workspaces = `GET /api/v1/workspaces`** (JÁ EXISTE, workspace-tenancy). Não preciso
   de mock; uso o endpoint real via `workspacesApi`/`membershipsApi`.
5. **Rotas em pt-BR** (`/minhas-tarefas`, `/relatorio`) conforme o proposal; as telas de destino
   são stubs/outlets (o conteúdo é de hierarchy-screens etc.).
6. **Migração de leitura do template (6.3):** a "única página que usa React Query" — identifico
   qual e realinho; coordeno para não portar leituras de Leads/WhatsApp (mortas, seal-template).
8. **Descarte por workspace ausente (5.7) reusa `handleAccessRevoked` (G5).** O carregador
   `useWorkspaceIndex` popula o índice e, se o workspace corrente não está no índice recém-carregado,
   dispara `handleAccessRevoked` (já existente em `accessRevoked.ts`): limpa cache do tenant, volta
   ao próprio, avisa. O 403 de request de domínio (papel adulterado) já é tratado pelo interceptor →
   mesmo caminho. Não dupliquei a rotina.
9. **"Fechar overlays" (D-A) é satisfeito pela escolha de item (5.4).** `switchWorkspace` faz
   cancelQueries → clear → reset → gravar wsId; a navegação e o fechar do menu ficam com o chamador
   (`WorkspaceContext.pick`): escolher um item do PortalMenu JÁ é um dos 5 gatilhos de fechamento, então
   o overlay fecha antes de `pick` navegar. Não adicionei fechamento imperativo redundante.
7. **`/` passa a ser a Visão Geral autenticada (G4).** A casca envolve toda a área autenticada
   (`ProtectedRoute > AppShell`), e o índice `/` é o destino "Visão Geral". A landing de marketing
   do template (HomePage), que ocupava `/`, foi movida para `/apresentacao` — reachable até
   `seal-template-baseline` decidir seu destino. Anônimo em `/` cai em `/entrar` pelo ProtectedRoute.
   As três telas de destino (`OverviewPage`/`MyTasksPage`/`ReportPage`) são STUBS: o conteúdo real
   vem de `hierarchy-screens`/`my-tasks-view`/`commissioning-report`.
10. **6.3 — não há página do template usando React Query para migrar (G6).** O único consumo de
    React Query no repo hoje é das FEATURES de domínio (`catalog`/`hierarchy`/`team`/`tasks`), já em
    chaves `['ws', wsId, …]` compatíveis com a factory. As páginas do template (Profile/Users) usam
    `apiClient` direto (não React Query) e são dívida do `seal-template-baseline`. Então 6.3 vira:
    VERIFICAR (nenhuma leitura a migrar) + LIGAR o guard em `main.tsx` (feito). As páginas legadas
    entram na allowlist do sweep 6.4.
11. **Guard tolera tenant `null` (query desabilitada) — não `''` (G6).** Todas as factories de chave
    aceitam `wsId: string | null` e montam `['ws', null, …]` enquanto `enabled: Boolean(wsId)` está
    falso (antes de um workspace ser escolhido). Como o guard checa FORMA (não é a barreira de
    vazamento — essa é o `clear()` + RLS), `isValidQueryKey` passou a aceitar tenant `null/undefined`
    (query pendente), mantendo `['projects']` (sem prefixo `ws`) e `['ws', '', …]` (string vazia = bug)
    como inválidos. Sem isto, o guard ligado em DEV derrubaria a app na janela de carga inicial.

## Armadilhas previstas

1. **Vazamento entre tenants no CLIENTE** (o risco nº 1): `clear()` (não `invalidate`), na ordem
   certa, com `cancelQueries` ANTES para a resposta atrasada de `betim` não escrever cache após a
   troca para `camacari`. Testes 5.5/5.6 são obrigatórios.
2. **Portal recortado**: `absolute` dentro da área rolável seria cortado por `overflow-y:auto`.
   Fixed + portal na raiz. Medição prévia sem pintar frame provisório.
3. **Guard de key ligado antes da migração** (6.3): ligaria e falharia o próprio dev. Ligar SÓ
   depois de migrar a página existente.
4. **Foco no Esc**: menu/modal devolvem foco ao gatilho (já provado no Modal).
5. **Frontend usa pnpm**; QueryClient defaults sensíveis (staleTime) travados por teste (1.4).

## Protocolo por grupo

Aplicar → `pnpm exec vitest run` (0 falhas) + `pnpm exec tsc --noEmit` + `pnpm build` quando tocar
config → marcar `- [x]` em tasks.md → `npx --yes @fission-ai/openspec@1.6.0 validate
app-shell-navigation --strict` → **um commit** `G<n>:`. Divergência design×realidade: decidir,
registrar aqui, seguir.

## Progresso

- [x] G0 — este mapa (commit G0)
- [x] G1 — Fundação D9 (1.1–1.4)
- [x] G2 — Dívida do token (2.1–2.4)
- [x] G3 — Menu em portal (3.1–3.6)
- [x] G4 — Casca/sidebar/topbar (4.1–4.6)
- [x] G5 — Contexto e troca de workspace (5.1–5.9)
- [x] G6 — Persistência e convenção (6.1–6.4)

## RETOMADA (para o próximo agente)

1. `git log --oneline` na branch `app-shell-navigation` (empilhada em `design-system`); um commit
   por grupo. `tasks.md` tem o estado fino; este arquivo tem as decisões.
2. Baseline: só frontend. `cd frontend && pnpm exec vitest run && pnpm exec tsc --noEmit`. pnpm.
3. LEIA a seção RECONCILIAÇÃO: token single-source, QueryClient extraído, workspaceStore e keys
   `['ws',…]` JÁ existem. Muita tarefa é alinhar/verificar, não construir do zero.
4. Invioláveis: `clear()` na troca (barreira de vazamento), key `['ws', wsId, …]` com guard,
   token fonte única, sidebar só destinos, papel=badge/workspace=select, índice de ws ≠ autorização.
5. Consumidores (as telas): `hierarchy-screens`, `robot-task-table`, `my-tasks-view`,
   `commissioning-report`, `workspace-settings`, `realtime-collaboration` (D6 — precisa saber qual
   key invalidar). A factory de keys e o contrato do indicador de gravação são para eles.
