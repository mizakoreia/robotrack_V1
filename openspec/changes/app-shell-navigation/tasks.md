# Tarefas — `app-shell-navigation`

Onda 2. Depende de `design-system` (tokens, escala de z-index, `Save indicator`, `Badge`)
e de `identity-and-auth` (sessão, usuário corrente, logout). O endpoint do índice de
workspaces vem de `workspace-tenancy`; até ele existir, os grupos 3 e 4 trabalham contra
um mock que segue o contrato acordado.

## 1. Fundação de estado de servidor (D9)

- [x] 1.1 Extrair o `QueryClient` de `frontend/src/main.tsx` para `lib/query/client.ts`
  com os defaults da convenção (`staleTime` 30s, `gcTime` 5min,
  `refetchOnWindowFocus: false`, `retry` 1 em query e 0 em mutation), importado por
  `main.tsx`. *(O QueryClient JÁ estava extraído em `lib/queryClient.ts` (identity-and-auth); alinhei os defaults: staleTime 5min->30s, gcTime 5min, mutations.retry 0.)* (§D9 — o handler de troca de workspace, que não é componente, consegue
  importar o cliente sem hook; hoje ele está preso dentro de `main.tsx` e seria
  inalcançável)
- [x] 1.2 Criar `lib/query/keys.ts` com a factory tipada de query keys
  (`ws`, `projects`, `project`, `cells`, `robot`, `tasks`, `my-tasks`, `notifications`,
  `search`) exigindo `wsId` no tipo. (§D9 — chamar a factory sem `wsId` não compila; um
  typo em `'projects'` deixa de ser possível porque não há mais array literal)
- [x] 1.3 Implementar o guard de forma de key assinando o `queryCache`: lança em `DEV` e
  `test`, reporta ao rastreio de erro em produção. (§D9 — registrar `['projects']` em
  teste falha com a key ofensora na mensagem; em produção o app não cai)
- [x] 1.4 Escrever o teste do guard e dos defaults do cliente, cobrindo key conforme, key
  sem prefixo `ws`, e `mutations.retry === 0`. (§D9 — o teste falha se alguém subir o
  `staleTime` de volta para os 5min do template)

## 2. Dívida do token

- [x] 2.1 Adicionar `setAuthTokenAccessor()` em `lib/api/client.ts` e substituir a leitura
  de `localStorage.getItem('access_token') || getItem('token')` pelo acessor; registrar o
  acessor em `main.tsx` antes do primeiro request. (§D-E — `lib/api/client.ts` deixa de
  conter a string `localStorage`, verificável por teste de varredura; e não importa
  `store/authStore` — sem ciclo) *(O token JÁ é fonte única no authStore (identity-and-auth); client.ts lê `useAuthStore.getState().accessToken`, sem `localStorage` e sem ciclo — o acessor injetado é desnecessário. Sweep de 'localStorage' em client.ts verde.)*
- [x] 2.2 Implementar a migração de boot das chaves legadas: hidrata o store se vazio e
  **remove** `access_token` e `token`. Precedida da leitura e escrita no store, para que a
  remoção nunca perca a única cópia do token. (§D-E — segundo boot não altera nada; boot
  sem chave legada conclui sem erro)
- [x] 2.3 Ligar o logout ao descarte: limpar store de auth e `queryClient.clear()` na
  mesma função usada pela troca de workspace. (§D-E — após sair, a requisição seguinte é
  emitida sem cabeçalho `Authorization`; hoje o interceptor continuaria injetando o token
  de `localStorage`)
- [x] 2.4 Teste de request de ponta a ponta com token no store, logout e migração legada,
  incluindo o caso "sem chave legada". (§D-E — falha se alguém reintroduzir leitura direta
  de `localStorage` no interceptor)

## 3. Primitivo de menu em portal

- [x] 3.1 Criar o contêiner `#rt-overlays` como filho direto de `<body>` e o `<PortalMenu>`
  com `createPortal`, `position: fixed` e `z-index` da camada `dropdown` da escala
  semântica de `design-system`. (§D-C — com a área de conteúdo rolada 400px, a altura
  visível do menu é igual à altura medida: nenhum recorte por `overflow-y: auto`)
- [x] 3.2 Implementar a medição prévia em layout effect: monta com `visibility: hidden`
  (nunca `display: none`), lê os retângulos e resolve direção vertical, alinhamento
  horizontal e altura máxima com rolagem interna. (§D-C — gatilho com `bottom = 780` numa
  viewport de 800px e menu de 220px abre para cima com `top >= 8`; nenhum frame pinta o
  menu em posição provisória)
- [x] 3.3 Implementar o fechamento: `pointerdown` fora, `Escape` com `stopPropagation`,
  `scroll` em capture no contêiner rolável e na janela, `resize`, e escolha de item — com
  devolução do foco ao gatilho. (§D-C — `Escape` deixa `document.activeElement` igual ao
  gatilho; o clique fora não aciona o card sob o ponteiro no mesmo gesto)
- [x] 3.4 Tratar o `resize` do teclado virtual: só fecha se a largura mudar ou a altura
  variar mais de 120px. (§D-C — `resize` com mesma largura e −80px de altura mantém o
  menu aberto no iOS Safari)
- [x] 3.5 Implementar navegação por teclado (`ArrowDown`/`ArrowUp` com ciclo, `Home`,
  `End`), `role="menu"`/`menuitem`, `aria-haspopup` e `aria-expanded` no gatilho.
  (§5.1 a11y — `ArrowUp` no primeiro de 3 itens leva ao terceiro; `aria-expanded` reflete
  o estado real)
- [x] 3.6 Escrever os testes do primitivo: abre para cima, abre para baixo, menu maior que
  a viewport, estouro à direita, os cinco gatilhos de fechamento, `Escape` sobre modal
  fechando só o menu. (§D-C — falha se alguém trocar o portal por `position: absolute`)

## 4. Casca, sidebar e topbar

- [x] 4.1 Criar `app/AppShell.tsx` e converter as rotas autenticadas de `app/App.tsx` em
  rotas-filhas do layout, mantendo `/login` fora. (§3.10 — navegar de `/` para
  `/minhas-tarefas` não remonta sidebar nem topbar, e só `.main` rola; `document.body` não
  ganha barra de rolagem)
- [x] 4.2 Implementar a sidebar com a constante fechada `NAV_DESTINATIONS` de 3 entradas e
  estado ativo por preenchimento tintado + ícone em `--accent`, sem `border-left` e sem
  pseudo-elemento de barra. (§DESIGN Navegação — a rota `/projeto/8f2a/celula/1c9b` mantém
  "Visão Geral" ativo; nenhum item de configuração aparece na sidebar para papel Dono)
- [x] 4.3 Implementar o rodapé da sidebar com o card de usuário (nome sobre e-mail,
  e-mail truncado com reticências, fallback para e-mail quando o nome é vazio) e o menu
  "Edição e visualização" de 3 itens. (§DESIGN Navegação — usuário sem nome não exibe o
  e-mail duas vezes)
- [x] 4.4 Implementar a topbar com o slot de contexto à esquerda, o slot nomeado para o
  gatilho de notificações e o menu da conta com "Adicionar usuário", "Alternar tema" e
  "Sair". (§3.10 — o slot de notificações vazio não desloca o layout da barra; para papel
  "Somente leitura" o item "Adicionar usuário" não é renderizado)
- [x] 4.5 Implementar a gaveta abaixo de 768px, com o indicador de gravação promovido à
  topbar enquanto ela está fechada e fechamento ao escolher destino. (§3.10 — a 375px com
  1 mutation em voo o estado `salvando` é visível sem abrir a gaveta)
- [x] 4.6 Escrever os testes de casca: contagem de destinos igual a 3, ausência de faixa
  lateral, `aria-current` no destino corrente, scroll ao topo na navegação, e render da
  topbar em 375px. (§3.10 — falha no momento em que alguém promover "Configurações" a
  quarto item da sidebar)

## 5. Contexto e troca de workspace

- [x] 5.1 Criar `store/workspaceStore.ts` com o `wsId` corrente e o índice de workspaces,
  expondo o `wsId` por um seletor único consumido por todos os hooks de domínio.
  (§3.10 — nenhum módulo lê o `wsId` de outra origem; escrita só pelo handler do 5.4)
- [x] 5.2 Implementar o contexto na topbar: seletor renderizado apenas com
  `workspaces.length > 1`, e nome como texto estático fora da ordem de tabulação quando há
  exatamente um. (§3.10 — com 1 workspace não existe elemento com `disabled` nem
  `aria-disabled`: o controle não é renderizado, não é desabilitado)
- [x] 5.3 Implementar o badge de papel com os rótulos "Dono" / "Editor" / "Somente
  leitura", estático, sem chevron e fora da ordem de tabulação; papel ausente cai para
  "Somente leitura". (§DESIGN Components — lado a lado, só o seletor tem chevron e só ele
  recebe `Tab`; badge é rótulo, select é controle)
- [x] 5.4 Implementar `switchWorkspace()` na ordem: fechar overlays → `cancelQueries()` →
  `queryClient.clear()` → resetar fatias de UI por workspace → gravar o novo `wsId` →
  navegar para `/`. (§3.10 — `getQueryCache().getAll()` retorna vazio imediatamente após a
  troca; `invalidateQueries` não é chamado no fluxo)
- [x] 5.5 Escrever o teste de vazamento entre tenants: cache quente com os projetos "Linha
  3" e "Linha 5" de `betim`, troca para `camacari`, e asserção de que esses textos nunca
  aparecem no documento em nenhum frame após a troca. (§3.10 — este teste é o que falha se
  alguém trocar `clear()` por `invalidateQueries()`, que renderiza o dado antigo enquanto
  refaz o fetch)
- [x] 5.6 Escrever o teste da resposta atrasada: query de `betim` em voo, troca para
  `camacari`, resposta chega 300ms depois e não escreve entrada com `wsId = 'betim'` no
  cache. (§3.10 — falha se o `cancelQueries()` for removido ou reordenado para depois do
  `clear()`)
- [x] 5.7 Implementar o tratamento de 403 e de workspace ausente do índice: recarregar o
  índice, atualizar o badge e, se o workspace corrente sumiu, executar o descarte completo
  e voltar ao workspace próprio com aviso. (§3.10 revogação — papel local adulterado de
  `view` para `owner` não concede escrita: o 403 é apresentado como erro do servidor, não
  tratado como bug de UI)
- [x] 5.8 Implementar a degradação do índice: falha de rede e índice vazio mantêm a casca
  navegável, sem seletor e sem badge, com ação de nova tentativa. (§3.10 — erro de rede no
  índice não impede a sidebar de renderizar)
- [x] 5.9 Escrever os testes restantes do contexto: seletor ausente com 1 workspace,
  presente com 2, badge para cada um dos 3 papéis, escolher o workspace já corrente sem
  efeito, e degradação com índice vazio e com erro de rede. (§3.10 — falha se alguém
  "melhorar" o caso de 1 workspace renderizando um seletor desabilitado)

## 6. Persistência, migração de leituras e trava da convenção

- [ ] 6.1 Criar `store/persistenceStore.ts` (não persistido) com `inFlight`, `queued`,
  `failed`, `lastSavedAt` e as três escritas `beginMutation` / `settleMutation` /
  `setQueueDepth`. (§D-D — `settleMutation` duplicado do mesmo id não leva `inFlight` a
  negativo; é o contrato contra o qual `offline-pwa` vai programar)
- [ ] 6.2 Implementar o indicador de gravação como projeção pura do store, na precedência
  `erro > salvando > salvo`, sem expiração por tempo. (§D-D — `queued = 3` com
  `inFlight = 0` exibe `salvando`, nunca `salvo`; `erro` continua após 60s sem atividade)
- [ ] 6.3 Migrar a única página do template que já usa React Query para a factory de keys e
  para `features/<dominio>/api/`, e ligar o guard do 1.3 somente depois. (§D9 — o guard
  ligado antes da migração falharia o próprio desenvolvimento; coordenar com
  `seal-template-baseline` para não portar leituras de Leads/WhatsApp/cobrança que serão
  deletadas)
- [ ] 6.4 Escrever a verificação automatizada de convenção que roda no CI: componentes não
  importam `lib/api/client`/`endpoints`; hooks de domínio moram em `features/*/api/`;
  nenhum store de Zustand guarda entidade de domínio; nenhuma mutation invalida
  `['ws', wsId]` inteiro; `createPortal` só aparece em `components/menu/`. (§D9 — falha
  nomeando o arquivo ofensor, e é o que impede as seis capacidades de tela de inventarem
  seis convenções em paralelo)
