# Design — `app-shell-navigation`

## Context

O legado é um PWA vanilla com uma única view montada em `.main` e menus escritos como
filhos do `<body>` com `position: fixed`. Essa escolha não é gosto: `.main` tem
`overflow-y: auto`, e um menu `absolute` dentro dele é **recortado** pela caixa de
rolagem. O `DESIGN.md` registra a mesma decisão, incluindo a medição prévia via
`.measuring`. O porte precisa reproduzir o comportamento em React sem perder o motivo.

O alvo (`frontend/`) chega com quatro fatos relevantes:

- Rotas inline em `app/App.tsx`, sem layout compartilhado, sem arquivo de configuração.
- `QueryClient` instanciado dentro de `main.tsx` — inacessível fora da árvore React, o
  que importa porque a troca de workspace precisa limpá-lo de fora de um componente.
- `staleTime` global de 5 minutos, `retry: 1`, `refetchOnWindowFocus: false`, e **uma**
  página consumindo React Query. O resto é `useEffect` + `apiClient` + `useState`.
- Token em dois lugares: `localStorage` (`access_token` ou `token`) lido diretamente no
  interceptor do `apiClient`, e `auth-storage` do Zustand persistido.

Também herdamos uma armadilha de segurança específica do porte: no Firestore, sair de um
workspace desmontava os `onSnapshot` e o estado morria junto. Um cache de query em
memória não tem esse ciclo de vida. **Servidor correto não basta.**

## Goals / Non-Goals

**Goals**
1. Casca navegável estável que as seis capacidades de tela pluguem sem negociar layout.
2. Zero registro de outro workspace visível na tela após uma troca, em qualquer instante
   — inclusive no frame entre a troca e a chegada do primeiro fetch.
3. D9 escrito como requisito executável: convenção de key, local dos hooks, política de
   `staleTime`/invalidação, fronteira do Zustand — com guard automatizado, não com
   convenção documentada e torcida.
4. Menus que se comportam: nunca recortados, nunca fora da viewport, sempre devolvendo o
   foco ao gatilho.
5. Uma fonte de verdade para o token.

**Non-Goals**
- Conteúdo de tela, painel de equipe, service worker, policies, modelo de workspace.
- Substituir a autorização do servidor por UI condicional.
- Gerenciar a fila offline — só consumir seu contador.

## Decisions

### D-A. Troca de workspace usa `queryClient.clear()`, não invalidação

**Decisão.** Ao trocar de workspace, na ordem exata:

1. Fechar todo menu aberto e abortar navegações pendentes.
2. `queryClient.cancelQueries()` — para que respostas em voo do workspace anterior não
   repovoem o cache **depois** da limpeza.
3. `queryClient.clear()` — **remove todas as queries e mutations do cache**, não marca
   como stale.
4. Resetar as fatias de UI escopadas por workspace do Zustand (filtros de tabela,
   agrupamento, seleção, busca) para o default.
5. Só então gravar o novo `wsId` no `workspaceStore` e navegar para `/`.

O `wsId` é lido de uma única fonte (`workspaceStore`), e todos os hooks de domínio o
consomem pelo mesmo seletor. Como toda query de domínio tem `wsId` no segundo segmento
da key, um remount depois do `clear()` só pode produzir keys do novo workspace.

**Alternativas descartadas:**

- **`invalidateQueries()`** — errado e perigoso. Invalidar marca como stale e **mantém
  os dados em cache**; o React Query os entrega imediatamente ao componente (o
  `placeholderData`/estado anterior) enquanto refaz o fetch em background. Isso é
  exatamente o vazamento: a tela do workspace B renderiza os robôs do workspace A por
  alguns frames. É o modo de falha que o §3.10 proíbe em letra.
- **`removeQueries({ queryKey: ['ws', prevWsId] })`** — correto em teoria, frágil na
  prática. Depende de **toda** query do app ter aderido à convenção. Uma única key mal
  formada — e o template já tem código fora do padrão — sobrevive à remoção e vaza. A
  varredura por prefixo transforma um erro de digitação em falha de isolamento.
  `clear()` não tem essa dependência: é correto mesmo com código não conforme.
- **Recarregar a página inteira (`window.location.reload()`)** — resolve o vazamento
  mas descarta a sessão, o service worker quente e a fila offline em memória, e produz
  um branco de ~1s no chão de fábrica com conexão ruim. Custo alto para um problema que
  `clear()` resolve.
- **Um `QueryClient` novo por workspace** (trocar o `client` do provider) — funciona e é
  elegante, mas força remount de toda a árvore e faz o `QueryClient` virar estado de
  render, complicando o acesso de fora da árvore. Mantido como plano B se `clear()` se
  mostrar insuficiente sob `realtime-collaboration`.

**Onde a invariante mora.** No cliente, em duas camadas: (a) o handler de troca é a
**única** via de escrita do `wsId`, e ele é um módulo que faz `cancel → clear → reset`
em sequência; (b) um **guard de forma de query key** instalado no `queryCache` que, em
desenvolvimento e em teste, **lança** quando uma query de domínio é registrada sem
`['ws', wsId, …]`. O guard é o que impede a convenção de apodrecer.

A barreira real continua sendo o servidor: RLS por `app.current_workspace_id` (D2) e
policies (D3). Esta decisão cobre o cliente, que é onde a spec aponta o dedo e onde
nenhuma outra capacidade olha. **A UI não é a garantia; é a segunda das duas.**

### D-B. D9 — a convenção de estado de servidor

**Decisão.**

*Forma da query key.* Toda leitura de domínio usa uma key construída por uma **factory
tipada**, nunca por array literal:

```
['ws', wsId]                                     raiz do workspace
['ws', wsId, 'projects']                         coleção
['ws', wsId, 'project', projectId]               entidade
['ws', wsId, 'project', projectId, 'cells']      coleção aninhada
['ws', wsId, 'robot', robotId, 'tasks']          conforme D9
['ws', wsId, 'my-tasks']
['ws', wsId, 'notifications']
```

Coleção no plural, entidade no singular seguida do id. Filtros de UI **não entram na
key** — filtro segmentado, agrupamento e busca são estado de cliente e filtram o
resultado já em memória; colocá-los na key multiplicaria entradas de cache e provocaria
refetch a cada clique de filtro (§3.5, cujo filtro reseta na navegação). Exceção: um
filtro que muda o conjunto que o servidor devolve entra na key como último segmento,
um objeto serializável.

*Onde os hooks moram.* `frontend/src/features/<dominio>/api/` — um módulo por domínio,
exportando a factory de keys e os hooks (`useProjects`, `useRobotTasks`, …). Nenhum
componente chama `apiClient` diretamente. `lib/api/endpoints.ts` continua sendo a camada
de transporte que os hooks consomem.

*Política de cache.* `staleTime` padrão de **30 segundos**, não os 5 minutos do
template. O motivo é D6: o `WorkspaceChannel` invalida a key correspondente a cada
mutação de domínio, então o cache é mantido fresco por push; os 30s cobrem só a janela
de reconexão do Cable e o fallback de polling. Cinco minutos com invalidação por push
seria inofensivo na maior parte do tempo e daria dados de dez minutos atrás justamente
quando o Cable cai — o pior momento. `gcTime` 5 minutos. `refetchOnWindowFocus`
permanece `false` (uso mobile alterna app o tempo todo). `retry: 1`, e **`retry: 0` para
mutations** — repetição de mutation é responsabilidade da fila offline (D7), não do
React Query, sob pena de duplo `+10` (§2.4).

*Invalidação.* Toda mutation declara explicitamente as keys que invalida, pelo prefixo
mais raso que ainda seja correto — um avanço de tarefa invalida
`['ws', wsId, 'robot', robotId]` inteiro, não só `…, 'tasks']`, porque o progresso do
robô muda junto (§2.1). Invalidar `['ws', wsId]` inteiro é proibido fora da troca de
workspace: derruba o app todo por um avanço.

*Fronteira do Zustand.* Zustand guarda **exclusivamente** estado que não existe no
servidor: tema, filtros e agrupamento de UI, estado do shell (gaveta aberta, menu
aberto), workspace corrente, fila offline e indicador de persistência, sessão/token.
Nenhuma entidade de domínio é copiada para o Zustand. Corolário: não há sincronização
manual entre store e cache, que é a classe de bug que o template já tem com o token.

**Alternativas descartadas:**
- **`wsId` implícito** (fora da key, lido de um contexto no fetcher) — a key deixa de
  identificar unicamente o dado, duas queries de workspaces diferentes colidem, e o
  `clear()` seletivo se torna impossível. É o desenho que produz o vazamento.
- **Manter `useEffect + apiClient + useState`** — é o padrão de fato do template. Não
  tem deduplicação, não tem invalidação endereçável, e D6 não teria o que invalidar.
- **Arrays literais em vez de factory** — um typo em `'projects'` cria silenciosamente
  uma segunda entrada de cache que nunca é invalidada. A factory dá tipo e ponto único.

**Onde a invariante mora.** No guard do `queryCache` (`onSuccess`/subscribe do cache),
ativo em `DEV` e em `test`, lançando em key não conforme; e num teste que percorre os
módulos de `features/*/api/` verificando que nenhum exporta hook sem usar a factory.
Convenção sem guard executável não sobrevive a seis capacidades paralelas.

### D-C. Menus em portal na raiz do documento, com medição prévia

**Decisão.** Um único primitivo `<PortalMenu>` renderiza via `createPortal` para um nó
`#rt-overlays`, **filho direto de `<body>`**, com `position: fixed`, `z-index` da camada
`dropdown` (60) da escala semântica de `design-system`.

Abertura em duas fases num mesmo commit, antes de qualquer pintura visível:
1. Monta com `visibility: hidden`, `position: fixed`, `top: 0; left: 0` — layout real,
   dimensões reais, sem flash. É o equivalente React da classe `.measuring` do legado.
2. Em layout effect, lê `getBoundingClientRect()` do gatilho e do menu e resolve:
   - **abaixo** se `triggerRect.bottom + menuH + 8 <= innerHeight`;
   - **acima** (`triggerRect.top - menuH - 8`) caso contrário;
   - se nenhum couber, escolhe o lado com mais espaço e limita a altura ao espaço
     disponível com rolagem interna;
   - horizontalmente alinha à borda de início do gatilho, deslocando para dentro se
     estourar a viewport, com margem mínima de 8px.
3. Torna visível e move o foco para o primeiro item.

Fechamento — todos devolvendo o foco ao gatilho, exceto quando o item escolhido navega:
`pointerdown` fora, `Escape` (`stopPropagation`, para não fechar um modal por baixo),
`scroll` em **capture** no contêiner rolável (`.main`) e na janela, `resize`, e escolha
de item.

**Alternativas descartadas:**
- **`position: absolute` no contêiner** — recortado por `overflow-y: auto` do conteúdo.
  É a razão original da escolha e não mudou.
- **Reposicionar continuamente no scroll** (estilo Floating UI `autoUpdate`) — mantém o
  menu colado, mas o `DESIGN.md` especifica **fechar** ao rolar, e fechar é o
  comportamento honesto: se o conteúdo se moveu, a intenção do usuário mudou. Também
  evita o custo de reflow por frame, que é caro junto do `background-attachment: fixed`
  da luz ambiente.
- **Adotar Radix `DropdownMenu`** — resolveria posicionamento e foco de graça, mas
  `components/ui/` do template é deliberadamente sem Radix e sem CVA (`design-system`
  registra isso), e Radix traria uma segunda gramática de componente para dentro de um
  sistema visual feito à mão. Custo de coerência maior que o benefício.
- **Portal direto em `document.body`** sem nó dedicado — funciona, mas um contêiner
  nomeado dá um ponto único para a escala de z-index e para limpar overlays órfãos na
  troca de workspace.

**Onde a invariante mora.** No primitivo. Nenhum componente de tela pode abrir menu
próprio: um teste de lint/estrutura verifica que `createPortal` não aparece fora de
`components/menu/`. Os listeners de scroll/resize/`Escape` vivem no primitivo e são
registrados só enquanto há menu aberto.

### D-D. Contrato do indicador de gravação (produtor: `offline-pwa`)

**Decisão.** Um `persistenceStore` (Zustand, **não** persistido) com:

```
inFlight: number        // mutations enviadas, sem resposta
queued: number          // mutations na fila offline aguardando envio (D7)
failed: number          // mutations que esgotaram retry ou viraram poison message
lastSavedAt: number|null
```

E três escritas, a API que `offline-pwa` implementa contra:
`beginMutation(id)` · `settleMutation(id, 'ok' | 'error')` · `setQueueDepth(n)`.

Estado derivado, nesta precedência:
- `failed > 0` → **`erro`** (pega precedência sobre tudo; sticky até `failed` zerar);
- `inFlight > 0 || queued > 0` → **`salvando`**;
- `lastSavedAt != null` → **`salvo`**;
- caso contrário → nada renderizado (antes da primeira mutação da sessão).

`salvo` **não expira sozinho**. Um indicador que apaga depois de 2s treina o usuário a
não confiar nele: a ausência do rótulo passa a significar duas coisas (nada aconteceu /
salvou e o rótulo sumiu). Honestidade do estado de persistência exige que o último fato
conhecido continue visível.

**Alternativas descartadas:**
- **Derivar do `isMutating()` do React Query** — só enxerga o que já saiu do cliente.
  Uma mutation enfileirada offline ficaria como `salvo`, que é a mentira exata que o
  indicador existe para não contar.
- **Toast em vez de indicador fixo** — `sonner` já está no projeto, mas toast é evento e
  desaparece; o estado de persistência precisa ser consultável a qualquer momento, e o
  usuário de luva não vai caçar um toast que sumiu.

**Onde a invariante mora.** No store: `failed` só zera por sucesso de reenvio ou por
descarte explícito do item pelo usuário, nunca por timeout. O indicador é uma projeção
pura — não tem estado próprio.

### D-E. Token com fonte única

**Decisão.** O token vive **apenas** no store de auth persistido (`auth-storage`). O
`apiClient` deixa de tocar em `localStorage` e passa a chamar um acessor injetado no
boot (`setAuthTokenAccessor(() => useAuthStore.getState().accessToken)`), configurado
em `main.tsx` antes de qualquer request. Injeção, e não `import` do store dentro do
`client.ts`, para não criar ciclo (`store → api → store`) e para manter o `apiClient`
testável sem montar o store.

Migração única no boot: se `localStorage.access_token` ou `localStorage.token` existir e
o store estiver vazio, hidrata o store e **remove** as chaves legadas. Idempotente e
segura para quem nunca teve as chaves.

**Alternativas descartadas:**
- **Consolidar em `localStorage` e o store lê de lá** — sentido oposto e pior: perde
  reatividade (mudança de token não re-renderiza), e `persist` do Zustand já escreve em
  `localStorage` de qualquer forma — teríamos duas chaves de novo.
- **Manter a sincronização manual** — é a dívida. Produz logout que não desloga: limpar
  o store sem limpar `localStorage` deixa o interceptor injetando `Bearer` de um token
  que a UI considera morto.

**Onde a invariante mora.** No `apiClient`, que não importa `localStorage` — verificável
por um teste que faz grep no módulo. E no handler de logout, que limpa store e cache
(`queryClient.clear()`) na mesma função da troca de workspace.

### D-F. Sidebar tem só destinos; configuração mora no rodapé

**Decisão.** Três itens na sidebar (Visão Geral, Minhas Tarefas, Relatório) e nada mais.
Tarefas/equipe/filtros, logs & histórico e backup entram pelo menu do card de usuário no
rodapé. Estado ativo = fundo tintado com accent + ícone em `--accent`; **sem faixa
lateral**, porque a faixa é elemento de 3–4px que some sob luz de galpão e concorre com
a borda de vidro (`.glass::after`) do `design-system`.

**Alternativa descartada:** promover Configurações a quarto item da sidebar. Achata a
hierarquia — configuração não é um *lugar onde se trabalha*, e o produto tem três — e
gasta o slot mais valioso da navegação com o destino menos visitado.

**Onde a invariante mora.** Numa constante de destinos (`NAV_DESTINATIONS`) com tipo
fechado, e num teste que afirma comprimento 3.

### D-G. Papel é badge, workspace é select — e nunca se parecem

**Decisão.** O badge de papel (Dono / Editor / Somente leitura) é pílula **estática**,
com texto em `--*-ink`, sem chevron, sem `cursor: pointer`. O seletor de workspace é
controle, com chevron do sprite obrigatório. Com **um** workspace, o seletor não é
renderizado como controle: vira texto do nome do workspace, sem chevron e fora da ordem
de tabulação. Regra dura do `DESIGN.md`, aplicada aqui porque é o único lugar do app
onde um badge e um select ficam lado a lado.

**Alternativa descartada:** renderizar o seletor sempre e desabilitá-lo com um só
workspace. Um controle desabilitado comunica "existe, você não pode" — falso; a verdade
é "não há o que escolher".

**Onde a invariante mora.** Na condição de render (`workspaces.length > 1`), com cenário
de teste dedicado.

### D-H. O índice de workspaces é cache de UI, nunca fonte de autorização

O seletor e o badge são alimentados por um endpoint de `workspace-tenancy`. O papel
exibido é informativo. Nenhuma decisão de escrita depende dele: o botão que um `view`
não pode usar pode até ser escondido, mas a negação é do servidor (invariante §4.1
nº 1 e nº 2, D3). Se o servidor responder 403 numa ação que a UI mostrava como
permitida, a UI **não** trata como bug de UI: exibe o erro e recarrega o índice de
workspaces — que é como a revogação em tempo real (`realtime-collaboration`) se
manifesta quando o Cable não chegou primeiro.

## Risks / Trade-offs

| Risco | Mitigação |
|---|---|
| `clear()` na troca joga fora cache legítimo compartilhado (ex.: catálogo de tarefas-base) e causa uma rajada de refetch. | Aceito conscientemente. Trocar de workspace é raro; vazar dado é inaceitável. Nada de "cache global fora do prefixo `ws`" — a exceção é justamente por onde o vazamento entraria. |
| Resposta em voo do workspace anterior repovoa o cache **depois** do `clear()`. | `cancelQueries()` antes do `clear()`, e o guard de key rejeita escrita com `wsId` diferente do corrente. Cenário de teste explícito. |
| `staleTime` de 30s aumenta refetch em relação aos 5min do template. | Trocado por frescor sob queda do Cable. Reavaliar com o orçamento de performance de `quality-and-accessibility`. |
| Guard de key lançando em produção quebraria o app. | Ativo apenas em `DEV` e `test`. Em produção, apenas reporta ao rastreio de erro (`delivery-and-observability`). |
| Medição prévia do menu causa flash em conexão lenta / máquina fraca. | Medição em layout effect, mesmo commit, `visibility: hidden` (não `display: none`, que zera dimensões). Nenhum paint intermediário visível. |
| `iOS Safari` dispara `resize` ao abrir o teclado virtual, fechando menus sem intenção. | Fechar em `resize` só quando a largura muda ou o delta de altura excede 120px. |
| Seis capacidades adotam a convenção parcialmente. | Guard executável no CI, não documentação. Ver tarefa 6.3. |

## Plano de migração

1. **`QueryClient` sai de `main.tsx`** para `lib/query/client.ts`, com os defaults da
   convenção. `main.tsx` passa a importá-lo. Sem mudança de comportamento observável.
2. **Acessor de token injetado**; migração das chaves legadas de `localStorage` roda uma
   vez no boot e as remove. Reversível: reverter o commit devolve a leitura direta, e o
   store já tem o token.
3. **`AppShell` introduzido** envolvendo as rotas autenticadas de `App.tsx`. Rotas
   públicas (login) ficam fora — `identity-and-auth` é dona delas.
4. **Migração de leituras existentes** para hooks: a única página do template que já usa
   React Query é realinhada à factory de keys. As demais leituras de domínio do template
   morrem com `seal-template-baseline` (Leads, WhatsApp, cobrança) e não precisam de
   porte — coordenar para não migrar código que será deletado.
5. **Guard de key ligado por último**, depois da migração, senão falha o próprio
   desenvolvimento durante a transição.

Nada destrutivo no servidor. A única remoção é de chaves de `localStorage` do próprio
navegador do usuário, precedida da hidratação do store — se ela falhar, o usuário refaz
login, e isso está coberto por `identity-and-auth`.

## Perguntas em aberto

1. **Notificações vivem no shell?** §2.7 dá 3 tipos e navegação por `ctx`. O sino
   provavelmente pertence à topbar, mas o `DESIGN.md` não o lista em "Navegação e IA".
   Assumimos que `in-app-notifications` traz o próprio gatilho e o monta num slot
   nomeado da topbar que expomos; o slot é entregue aqui, o conteúdo não.
2. **Rolagem preserva posição entre destinos da sidebar?** §3.5 exige que o filtro
   segmentado **resete** na navegação; por simetria assumimos scroll ao topo em toda
   troca de destino. Confirmar com `robot-task-table`.
3. **Deep link para workspace na URL** (`/w/:wsId/...`) versus workspace só no store. A
   URL seria mais honesta e tornaria o vazamento estruturalmente impossível, mas
   reescreve o esquema de rotas de todas as telas. Ficou **fora** desta capacidade;
   registrado como a evolução natural se o `clear()` se mostrar insuficiente.
4. **Ordenação do seletor de workspace** com muitos workspaces — assumimos "próprio
   primeiro, depois alfabético". Sem busca no seletor até haver evidência de necessidade.

## Fora de escopo por priorização

Atalhos de teclado globais para os três destinos, breadcrumb na topbar e persistência do
estado colapsado da sidebar entre sessões ficaram de fora para manter a contagem de
tarefas dentro do teto. Nenhum deles é citado em §3.10 ou no `DESIGN.md`.
