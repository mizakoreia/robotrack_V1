# design — hierarchy-screens

## Context

Cobre §3.2, §3.3, §3.4 e §3.7 da ESPECIFICACAO.md. É a camada de leitura da hierarquia
Projeto → Célula → Robô. Onda 7: `progress-rollup` e `app-shell-navigation` já existem
quando isto começa.

O legado montava estas telas a partir de um `onSnapshot` sobre a árvore inteira do
workspace no Firestore e reduzia tudo em JavaScript — daí a facilidade de ter duas
métricas divergentes sem ninguém notar: ambas saíam do mesmo array em memória. No porte,
o cliente **não tem** a árvore; ele tem endpoints agregados. Isso resolve o custo de
consulta e cria o risco oposto: se o servidor devolver um campo `progress` só, o
front preenche anel e hub com o mesmo número e a divergência de D15 desaparece
silenciosamente. Metade das decisões abaixo existe para tornar esse erro impossível de
cometer sem quebrar um teste.

Dois usuários, dois contextos: desktop para planejar (grade de 3–4 colunas) e celular de
luva sob luz de galpão (uma coluna, alvos ≥ 32px, teclado com tecla "buscar").

## Goals / Non-Goals

**Goals**
1. Três telas navegáveis, cada uma com hub analítico + grade de cards + estados vazio,
   carregando e erro.
2. As duas métricas exibidas lado a lado, **nomeadas de forma diferente na API e na UI**,
   com teste sobre dataset divergente.
3. Busca §3.7 completa, incluindo o disparo pela tecla "buscar" do teclado mobile.
4. Custo de consulta constante em número de queries por tela, independente de N.

**Non-Goals**
- Calcular progresso (é `progress-rollup`), mutar hierarquia (é
  `commissioning-hierarchy`), desenhar componentes (é `design-system`).
- Busca em tarefas, em comentários ou fuzzy/typo-tolerant.
- Paginação infinita da grade (ver "Perguntas em aberto").

## Decisions

### D-A. Duas métricas = dois campos com nomes distintos no contrato da API

O payload de cada card e de cada hub carrega campos **separados e explicitamente
nomeados**: `weighted_progress` (§2.1, o anel) e `raw_completion` (§3.2, o hub, um objeto
`{completed, total, percent}`). Não existe campo chamado `progress` em lugar nenhum
destes endpoints.

*Onde a invariante mora:* no **contrato**, e é policiada por três coisas somadas —
(1) o schema Grape/grape-entity, que não expõe `progress`; (2) um **spec de request** que
falha se a chave `progress` aparecer em qualquer resposta destes 4 endpoints; (3) o tipo
TypeScript do cliente, sem campo genérico. O componente `ProgressRing` de `design-system`
recebe a prop nomeada `weightedProgress`; o `HubBar` recebe `rawCompletion`. Trocar um
pelo outro é erro de tipo, não erro de leitura de código.

*Alternativa descartada:* um único campo `progress` com um parâmetro `?metric=weighted|raw`.
Descartada porque a Visão Geral precisa **das duas ao mesmo tempo** — obrigaria a duas
chamadas por tela e, pior, tornaria a confusão um erro de string, invisível ao compilador.

### D-B. Rótulo textual é parte do requisito, não do capricho visual

Todo lugar que exibe um dos dois números exibe também seu rótulo, em pt-BR, vindo do
módulo único de strings (D14): o hub usa **"de progresso físico global"** (Visão Geral) /
**"de progresso físico"** (Projeto e Célula) e o anel do card recebe `aria-label`
**"Progresso ponderado: N%"**. O anel não ganha rótulo visível dentro do card (não cabe e
polui a grade); ganha rótulo acessível e uma legenda única no cabeçalho da grade
("Anéis: progresso ponderado por peso de tarefa").

*Onde a invariante mora:* no **teste de componente** — a asserção é sobre o texto/`aria-label`
renderizado, não sobre a prop passada.

*Alternativa descartada:* tooltip explicativo só no hover. Descartada: no celular de luva
não existe hover, e é justamente o operador de campo quem confunde os dois números.

### D-C. Um endpoint agregado por tela, orçamento de query fixo

Cada tela faz **uma** chamada HTTP. O serviço agregador correspondente respeita o
**orçamento de query definido por `progress-rollup` (D5)**: o progresso ponderado é lido
da coluna `progress_cache` já materializada no nível do card, nunca recalculado por linha.
Orçamento por request, verificado em teste:

| Endpoint | Queries SQL |
|---|---|
| `GET /workspaces/:id/overview` | ≤ 3 (projetos + `progress_cache`; contagem de células por projeto; agregado global de tarefas) |
| `GET /projects/:id/overview` | ≤ 3 |
| `GET /cells/:id/overview` | ≤ 3 |
| `GET /workspaces/:id/search?q=` | ≤ 3 (uma por tipo: projects, cells, robots) |

O teto é **constante em N**: 50 projetos e 1 projeto custam o mesmo número de queries.

*Onde a invariante mora:* num **spec de request que conta queries** via
`ActiveSupport::Notifications.subscribe('sql.active_record')` sobre um dataset de 20
projetos × 5 células × 8 robôs, falhando acima do teto. Sem esse contador, um N+1
reintroduzido por um `map` inocente passa despercebido — a resposta continua correta.

*Alternativa descartada:* deixar o cliente pedir o progresso de cada card em paralelo com
React Query (`useQueries`). Descartada: 50 requisições HTTP na entrada do app, sob rede de
galpão, é pior que qualquer N+1 no servidor.

### D-D. A busca é server-side e volta em lista plana já com caminho resolvido

`GET /workspaces/:id/search?q=sol` devolve `{results: [...], count: N}` onde cada item é
`{type: "project"|"cell"|"robot", id, name, path_label, route}`. O `path_label` é montado
**no servidor** (`"Célula · em <projeto>"`, `"Robô · em <célula> · <projeto>"`), com
format string versionada de D14.

*Onde a invariante mora:* o filtro é `ILIKE '%' || :q || '%'` no Postgres, com o `q`
escapado para `%`, `_` e `\` (senão buscar `%` retorna o workspace inteiro). O escape é
testado. O **escopo de tenant é a RLS de D2**, não o `WHERE` — a query nem menciona
`workspace_id` no filtro de busca; a policy de leitura vem de `authorization-policies`.

*Alternativa descartada nº1:* busca client-side sobre uma árvore pré-carregada (como o
legado). Descartada: exige baixar toda a hierarquia na Visão Geral, exatamente o custo que
D-C evita.
*Alternativa descartada nº2:* `pg_trgm` / full-text com ranking. Descartada por
superdimensionamento — a spec pede substring case-insensitive, e ranking mudaria a ordem
esperada dos resultados sem que ninguém tenha pedido. Ordem é fixa e previsível:
projetos → células → robôs, cada grupo por nome ascendente.

### D-E. A busca substitui a visão via estado derivado do termo, não de uma flag

`isSearching = debouncedQuery.trim().length > 0`. Hub e grade não são desmontados por um
booleano separado que alguém possa esquecer de resetar; são renderizados condicionalmente
a partir do próprio termo. Limpar o campo restaura por construção.

*Onde a invariante mora:* no **componente**, e num teste que digita "sol", verifica que o
hub sumiu, limpa e verifica que o hub voltou com os mesmos números.

*Alternativa descartada:* rota `/search?q=` separada. Descartada: a spec diz "campo na
Visão Geral" e "os resultados substituem o hub e a grade" — é a mesma tela. O termo **não**
vai para a URL, então recarregar a página devolve a Visão Geral íntegra, que é o
comportamento esperado de um campo de busca efêmero.

### D-F. Quatro gatilhos, um caminho de código

Digitação ao vivo (debounce 250 ms), Enter, botão Buscar e a tecla "buscar" do teclado
mobile convergem no mesmo `submit`. Isso se obtém envolvendo o campo num `<form
role="search" onSubmit>` com `<input type="search" enterKeyHint="search"
inputMode="search">`: Enter e a tecla mobile disparam `submit` nativamente; o botão é
`type="submit"`; a digitação chama a mesma função por debounce. O `onSubmit` faz
`preventDefault` e força o flush do debounce (busca imediata sem esperar os 250 ms).

*Onde a invariante mora:* no markup (`<form>` + `enterKeyHint`), coberto por teste que
dispara `submit` e por auditoria manual em iOS/Android registrada em
`quality-and-accessibility`.

*Alternativa descartada:* `onKeyDown` capturando `Enter`. Descartada: em vários teclados
móveis a tecla "buscar" **não** emite `keydown` de `Enter` — emite `submit` do formulário.
Foi exatamente essa a razão de a spec listar os quatro gatilhos separadamente.

### D-G. Estados vazios são três, não um

(a) **Workspace sem projeto nenhum** → estado dedicado com CTA "Novo Projeto" (§3.2).
(b) **Projeto sem célula / célula sem robô** → estado vazio do nível, com o CTA daquele
nível. (c) **Busca sem acerto** → estado vazio que **nomeia o termo** (`Nenhum resultado
para "xyz"`), com botão limpar. São textos e CTAs distintos porque a ação correta é
distinta; unificá-los produz um "nada aqui" que não diz o que fazer.

Para papel `view` (§4.1) o CTA de criação **não é renderizado** e o texto do estado vazio
muda para a variante sem ação. A UI não é a garantia — a policy do endpoint de criação é,
em `authorization-policies`.

### D-H. Cards e grade seguem as regras de componente de §5.2

Badge em **linha própria** junto ao título (senão quebra em uns cards e não em outros e os
anéis da grade desalinham); cards da mesma linha com altura igual (grid com
`align-items: stretch`, sem altura fixa); anel a 0% **omite o traço**. Nada disso é
reimplementado aqui — é o contrato de uso dos componentes de `design-system`, e a grade
tem um teste visual de alinhamento com nomes de projeto de 3 e de 60 caracteres na mesma
linha.

### D-I. Chaves de cache e invalidação

Seguindo D9: `['ws', wsId, 'overview']`, `['ws', wsId, 'project', projectId, 'overview']`,
`['ws', wsId, 'cell', cellId, 'overview']`, `['ws', wsId, 'search', debouncedQuery]`.
A busca usa `staleTime: 30s` e `placeholderData: keepPreviousData` para não piscar entre
teclas. Um avanço de tarefa muda o progresso de três níveis — quem invalida essas keys é
`realtime-collaboration` (D6); aqui só se **declara e documenta** o conjunto exato de keys
que um evento de avanço deve derrubar, para que a outra capacidade não tenha que
adivinhar.

## Risks / Trade-offs

- **Risco principal (D15).** Alguém "simplifica" e faz o anel ler `raw_completion`. Em
  dataset uniforme os números batem e o teste passa. Mitigação: a fixture obrigatória
  `divergent_progress` — projeto com uma tarefa de peso 5 a 100% e três de peso 1 a 0% →
  **ponderado 40 %**, contagem crua **25 %** (1 de 4 concluídas). Todo teste que toca as
  duas métricas usa essa fixture; se alguém unificar, os dois valores param de divergir e
  o teste quebra.
- **`progress_cache` desatualizado.** A tela exibe o cache de D5 e herda qualquer
  divergência dele. Não se compensa aqui (recalcular na leitura mataria D-C); confia-se no
  job de reconciliação de `progress-rollup` e no alerta citado em
  `delivery-and-observability`.
- **Grade sem paginação.** 200 projetos renderizam 200 cards. Aceito para v1 (o dataset
  real é dezenas), mas o dataset de carga precisa medir; se estourar o orçamento de
  performance, a saída é virtualização da grade, não paginação (que quebraria a leitura
  macro).
- **Debounce de 250 ms.** Rápido demais gera requisição por tecla; lento demais parece
  travado sob rede de galpão. 250 ms + `keepPreviousData` é o compromisso; é um número a
  revisar com medição real.
- **Busca sem acento-insensibilidade.** `ILIKE` não casa "celula" com "Célula". A spec
  pede apenas case-insensitive, então fica assim — registrado como pergunta em aberto, não
  como bug.

## Plano de migração

Nenhuma migration. Nenhum dado existente. As telas passam a existir junto com as rotas
declaradas por `app-shell-navigation`; até `commissioning-hierarchy` popular dados, todas
exibem o estado vazio de D-G — o que é o comportamento correto e serve como primeiro
teste de integração de ponta a ponta.

## Perguntas em aberto

1. Busca deve normalizar acentos (`unaccent`)? Fora do que a spec pede; barato de somar
   depois via índice de expressão.
2. A grade de projetos precisa de ordenação manual (`position`, §2.9) já na v1, ou nome
   ascendente basta? Depende do que `commissioning-hierarchy` expuser.
3. Ao trocar de workspace, o termo de busca deve ser limpo? Assumido que sim (o shell
   descarta estado na troca, D9/`app-shell-navigation`) — a confirmar com aquela
   capacidade.
