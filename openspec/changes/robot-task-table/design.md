# Design — robot-task-table

## Context

`§3.5` descreve uma única tela com seis colunas heterogêneas, dois modais, dois
avisos derivados e um refluxo mobile. O legado a implementava como uma função
`renderRobot()` que montava a `<table>` inteira por concatenação de string a cada
mutação, lendo estado de variáveis globais (`currentFilter`, `currentRobot`). Três
consequências herdadas que o porte precisa eliminar:

1. O filtro vivia em global e só era zerado em alguns caminhos de navegação — a spec
   diz "reseta a cada navegação" justamente porque o legado *quase* fazia isso.
2. Cada mudança de slider disparava re-render total; o valor lido pelos botões
   `±10` vinha às vezes do DOM já reescrito, produzindo o bug de "+10 duas vezes =
   +10" que `§2.4` explicitamente proíbe.
3. `history` era array embutido no documento da tarefa; contar entradas e pegar o
   último comentário era grátis. No relacional isso vira agregação — se feita
   ingenuamente, é N+1 por linha da tabela.

Consumidores diretos: `offline-pwa` (Onda 9) monta a fila de mutations sobre os
gatilhos desta tela. Fornecedores: `progress-advances` (modal e trilha),
`progress-rollup` (percentual do cabeçalho), `robot-tasks` (esquema e CRUD),
`task-catalog` (`§2.6`), `design-system` (componentes), `app-shell-navigation`
(roteamento e D9), `workspace-tenancy` (`people`, D10/D11),
`authorization-policies` (D3).

## Goals / Non-Goals

**Goals**

- Reproduzir `§3.5` integralmente com comportamento observável idêntico.
- Tornar a tela utilizável com o polegar, de luva: alvos ≥ 32px, sem hover como
  único canal de informação, sem alvo menor que o dedo em qualquer breakpoint.
- Permitir que 3–4 pessoas trabalhem na tela **em paralelo** depois que o esqueleto
  existir — as colunas Responsáveis, Trilha e Ações não dependem uma da outra.
- Zero N+1: uma requisição devolve a tabela pronta, incluindo agregados de trilha.
- Nenhuma regra de avanço reimplementada aqui.

**Non-Goals**

- Não reimplementar o modal de avanço, o cálculo de progresso, o CRUD de tarefa nem
  a regra de sincronização de tarefas-base.
- Não introduzir virtualização de lista nesta rodada (ver "Ficou de fora").
- Não implementar edição inline de descrição na célula da tabela — `§3.5` pede uma
  ação "Editar descrição", que abre prompt/modal simples do `design-system`.
- Não implementar drag & drop de reordenação de tarefas aqui
  (`commissioning-hierarchy` é dono de `position`).

## Decisions

### D-RTT-1 — O filtro é estado de UI efêmero, chaveado por rota, e reseta na navegação

O filtro segmentado vive num store Zustand `robotTaskFilterStore` com um único campo
`filter` e um efeito de rota que o força a `"all"` sempre que `robotId` muda **e**
sempre que a tela monta. Concretamente: o componente de tela chama
`resetFilter()` num `useEffect` cuja dependência é `robotId`, e a rota é montada com
`key={robotId}` — dois mecanismos porque o primeiro sozinho não cobre "sair do robô
A e voltar ao robô A" (mesmo `robotId`, `useEffect` não redispara se a árvore não
desmontou; o `key` garante o desmonte).

**Alternativa descartada:** persistir o filtro na URL (`?status=pending`). Ela é
sedutora (link compartilhável, botão voltar funciona) mas **contradiz a spec**: com
o filtro na URL, voltar ao robô restaura o filtro anterior, que é exatamente o
comportamento que `§3.5` proíbe. Também descartada: `persist` do Zustand — mesma
contradição, agravada por sobreviver a recarga.

**Onde mora a invariante:** teste de componente + E2E (`quality-and-accessibility`)
navegando robô A → robô B → robô A e asserindo "Todos". Não é invariante de dados;
não tem representação no banco. Declarado explicitamente para que ninguém "melhore"
a tela adicionando persistência de filtro depois.

### D-RTT-2 — O filtro é derivado de `status`, não de `progress`

`Pendentes` = `status IN ('Pendente','Em Andamento')`. `Concluídos` =
`status = 'Concluído'`. `N/A` **não aparece em nenhum dos dois** — só em "Todos".
Isso decorre de `§2.2`: status e progresso são acoplados, e `N/A` tem progresso 0 sem
ser trabalho pendente. Filtrar por `progress < 100` colocaria `N/A` em "Pendentes" e
daria ao operador uma lista de trabalho que inclui itens que ninguém vai fazer.

**Alternativa descartada:** filtro por faixa de progresso. Descartada pelo motivo
acima e porque quebraria assim que `progress-rollup` mudasse a semântica de `N/A`.

**Onde mora:** filtro aplicado **no cliente**, sobre o payload já carregado (a tabela
inteira de um robô é dezenas de linhas, não milhares). O servidor não recebe
parâmetro de filtro — o que também impede que o filtro vaze para cache de query key.

### D-RTT-3 — Um único endpoint agregado, com os agregados de trilha calculados em SQL

`GET /api/v1/robots/:id/tasks` devolve cada tarefa com:
`assignees[] {person_id, name}`, `contributors[] {person_id, name}`,
`advances_count`, `last_advance {comment, recorded_at, author_name_snapshot}`.
`contributors` e `advances_count` vêm de um `LEFT JOIN LATERAL` sobre
`task_advances` agrupado por `task_id`; `last_advance` de um segundo `LATERAL`
ordenado por `recorded_at DESC, created_at DESC` com `LIMIT 1` (o desempate por
`created_at` existe porque `recorded_at` vem do cliente, D8, e dois avanços offline
podem colidir no mesmo instante).

**Alternativa descartada (a):** deixar o cliente pedir `/tasks/:id/advances` por
linha para montar "último comentário" e contagem — N+1 por linha, inaceitável numa
tela de galpão com rede ruim. **Alternativa descartada (b):** desnormalizar
`advances_count` e `last_advance_id` em `tasks` com trigger. Foi considerada
seriamente e rejeitada nesta rodada: `progress-advances` é append-only e a
cardinalidade por tarefa é baixa (dezenas), então o `LATERAL` é barato; adicionar um
segundo cache além do `progress_cache` (D5) dobra a superfície de divergência sem
ganho medido. Se o job de reconciliação de D5 mostrar custo de leitura, reavaliar —
registrado em "Perguntas em aberto".

**Onde mora:** índice `(task_id, recorded_at DESC)` em `task_advances`, criado nesta
capacidade se `progress-advances` não o criou. Isolamento entre tenants continua
sendo da **RLS** (D2), não do endpoint; o endpoint não filtra `workspace_id` na mão.

### D-RTT-4 — Responsável e contribuidor são conjuntos distintos e nunca são mesclados

`assignees` vem de `task_assignees` (quem é responsável **agora**, `robot-tasks`).
`contributors` vem de `DISTINCT person_id` em `task_advances` (quem **já registrou**
avanço). São conjuntos independentes: uma pessoa pode ser responsável sem nunca ter
registrado nada, e pode ter registrado avanço e depois ser desatribuída. A UI usa
**chip primário** (`Chip variant="assignee"`) para responsáveis e **chip secundário**
(`Chip variant="contributor"`) para contribuidores, e um contribuidor que **também**
é responsável aparece **só** como chip primário (a intersecção é subtraída da lista
secundária, para não duplicar o mesmo nome na mesma célula).

**Alternativa descartada:** exibir uma lista única de "pessoas envolvidas". Perde a
distinção que a tela existe para mostrar — o aviso "Atribuir…" depende justamente de
`assignees` estar vazio *mesmo havendo* contribuidores (cenário real: alguém passou e
registrou avanço via auto-atribuição `§2.3`, depois foi removido).

**Onde mora:** a distinção é estrutural (duas tabelas), não convenção de UI. O
endpoint devolve os dois arrays separados; a subtração da intersecção é do
componente, e é a única lógica de conjunto que vive no cliente.

### D-RTT-5 — Slider é controle otimista *reversível*: o valor exibido nunca diverge do persistido sem modal aberto

O slider mantém dois valores: `persisted` (o do servidor) e `draft` (o do arraste).
Enquanto o modal de avanço está aberto, o slider mostra `draft`. Ao **confirmar**,
`persisted` vira o valor retornado pelo servidor (não o `draft` — o servidor pode
ajustar por `§2.2`, ex.: `to = 100` → status `Concluído`). Ao **cancelar** ou em erro,
`draft` é descartado e o slider volta a `persisted`, conforme `§2.4` item 5.
Os botões `−`/`+` calculam a partir de `persisted`, **nunca** de `draft` nem do DOM —
é a regra que impede o bug de "+10 duas vezes = +10" de `§2.4` item 1.

**Alternativa descartada:** slider não controlado com leitura do DOM no submit. É
exatamente o padrão do legado e a causa raiz do bug citado.

**Onde mora:** no componente `ProgressCell` (fonte única `persisted` vinda da query
do React Query, nunca de `useState` inicializado uma vez) + teste que faz dois `+`
consecutivos sem recarregar e assere `+20`.

### D-RTT-6 — O aviso de trilha faltando perde a cláusula "nem nota" (ajuste declarado)

`§3.5` diz: `0 < progresso < 100` e **nenhum histórico nem nota** → "Registre o
avanço…". A "nota" é o campo legado `obs` (`§1.1`, `§1.4`). Por decisão de
`progress-advances`, o esquema novo **não carrega `obs`**; a nota legada é convertida
em uma entrada de `task_advances` com `legacy: true` pelo importador
(`legacy-data-migration`). Condição no esquema novo:

```
0 < progress < 100  AND  advances_count = 0
```

Consequência verificável: uma tarefa migrada que tinha `obs` preenchida e nenhum
`history` chega ao porte com `advances_count = 1` e portanto **não** exibe o aviso —
mesmo resultado observável de antes, por outro caminho. Se o importador falhar em
converter a nota, o aviso aparece; isso é um detector desejável, não um bug desta
tela.

**Alternativa descartada:** manter uma coluna `obs` só para alimentar a condição do
aviso. Perpetuaria um campo legado no esquema novo em troca de uma cláusula de
`if` — e criaria uma segunda fonte de "trilha" que nenhum outro consumidor lê.

**Onde mora:** a condição é derivada na UI a partir de `advances_count`; a garantia
real mora na `legacy-data-migration` (validação por amostra: toda tarefa de origem
com `obs` não vazia tem ≥1 `task_advance` `legacy` no destino).

### D-RTT-7 — Avisos são adornos não bloqueantes dentro da própria célula

"Atribuir…" renderiza **dentro da célula Responsáveis**, como botão que abre o modal
de atribuição. "Registre o avanço…" renderiza **dentro da célula Trilha**, como botão
que abre o modal de avanço. Ambos com ícone de alerta (`lucide`, `currentColor`,
`aria-hidden`) e texto acessível — nunca só o ícone. Nenhum dos dois bloqueia
qualquer ação, altera o status, ou impede salvar.

**Alternativa descartada:** banner no topo da tela listando tarefas incompletas.
Descartada porque tira o aviso do contexto da linha e obriga o operador a correlacionar
lista com tabela no celular — o oposto do que a tela precisa.

**Onde mora:** puramente derivado na render, sem estado. Sem persistência, sem
"dispensar aviso" — o aviso some quando a condição some.

### D-RTT-8 — Refluxo mobile por cartões reais, não por tabela rolável

Abaixo de `md`, a tabela é substituída por uma lista de cartões (`role="list"`), um
por tarefa, com o cabeçalho de categoria como separador de seção. Cada cartão
empilha: descrição → StatusSelect em largura total → linha de progresso
(`−` 40px · slider · `+` 40px · leitura `%` com `tabular-nums`) → chips → linha de
trilha → ações. Alvos: **mínimo 40px** nos controles de progresso e ações (a spec
exige ≥32px; adotamos 40 nos alvos de uso repetido, com 32 como piso absoluto para
os demais). O slider recebe `touch-action: pan-y` para não sequestrar o scroll
vertical.

**Alternativa descartada:** manter `<table>` com `overflow-x: auto`. Rolagem
horizontal com luva é a pior interação possível e esconde as colunas Ações e Trilha
justamente nas telas onde elas são mais usadas.

**Onde mora:** `md:` breakpoint do Tailwind; teste de a11y/tamanho de alvo em
`quality-and-accessibility` com viewport de 375px.

### D-RTT-9 — Papel `view` remove os controles do DOM, não os desabilita — e o servidor é a garantia

Com papel `view` (`§4.1`): sem "Adicionar tarefa", sem "Sincronizar tarefas-base",
sem coluna Ações, StatusSelect renderizado como `Badge` estático (nunca como select
desabilitado — DESIGN.md: "badge é rótulo, seletor é controle"), slider e `±`
ausentes, chips não clicáveis, modal de histórico **disponível** (é leitura), modal
de atribuição indisponível.

**Alternativa descartada:** renderizar tudo com `disabled`. Um select desabilitado
ainda *parece* controle, e a regra dura do DESIGN.md proíbe. Além disso deixa alvos
mortos ocupando espaço precioso no mobile.

**Onde mora:** a UI é conveniência (`§4.1` inv. 1). A garantia mora nas **policies**
(D3) dos endpoints de tarefa/avanço/atribuição, com route-sweep no CI, e na **RLS**
(D2) para o isolamento entre workspaces. Esta capacidade adiciona testes de request
que confirmam 403 para `view` em cada mutação que a tela dispara.

### D-RTT-10 — Query keys e invalidação declaradas para o consumo de tempo real

Chave única da tela: `['ws', wsId, 'robot', robotId, 'tasks']` (D9). Toda mutação
disparada aqui invalida essa chave **e** `['ws', wsId, 'projects']` (o percentual
consolidado sobe pela hierarquia, D5). `realtime-collaboration` publica eventos de
domínio e invalida a mesma chave — por isso ela é declarada aqui, no consumidor, e
citada lá.

**Alternativa descartada:** chave por tarefa (`[..., 'task', taskId]`). Multiplicaria
requisições e quebraria o agregado único de D-RTT-3.

### D-RTT-11 — A tela é decomposta para permitir paralelismo real de execução

O plano anterior modelava `§3.5` como cadeia linear de 7 tarefas sequenciais, o que
tornava impossível dividir a tela entre pessoas. É falso: dado o **esqueleto** (rota,
query agregada, tipos, layout de grupo/linha, contrato `TaskRow`), as colunas
**Responsáveis**, **Trilha** e **Ações** não se tocam — cada uma consome campos
distintos do mesmo objeto e não compartilha estado. O mesmo vale para os dois modais
entre si.

Estrutura adotada em `tasks.md`: um grupo **1 (esqueleto)** estritamente sequencial e
bloqueante, e depois **quatro trilhas independentes** (colunas de mutação · colunas
de leitura e avisos · modais · mobile+a11y) que podem correr em paralelo, convergindo
num grupo final de integração. Isso está dito no `tasks.md` como nota de
paralelismo, não implícito na numeração.

**Alternativa descartada:** manter a cadeia linear "porque é uma tela só". Uma tela
não é uma unidade de trabalho; um contrato de dados é.

## Risks / Trade-offs

- **Contrato agregado acopla esta tela a `progress-advances`.** Se aquela capacidade
  renomear `recorded_at` ou o marcador `legacy`, a entity quebra. Mitigação: a entity
  é serializada por `Api::Entities::TaskRow` com spec de contrato que falha se um
  campo sumir, e o campo de data é explicitamente `recorded_at` (D8) — nunca
  `created_at`, que continua existindo e é o erro fácil de cometer.
- **Filtro no cliente não escala** se um robô tiver milhares de tarefas. O legado e o
  domínio (31 tarefas-base em 9 categorias, `§1.2`) dizem dezenas. Se o dataset de
  carga de `quality-and-accessibility` mostrar robôs com >500 tarefas, mover filtro e
  paginação para o servidor — o que reintroduz o filtro na query key.
- **Dois mecanismos de reset de filtro** (`key` de rota + `useEffect`) é redundância
  deliberada. Custo: um desmonte de árvore a cada troca de robô, perdendo scroll.
  Aceito — a spec quer a tela zerada.
- **Pulso aos 100% pode disparar em avanço de outra pessoa** chegando por
  ActionCable. É desejável (feedback de colaboração ao vivo) mas pode surpreender.
  Mitigação: o pulso dispara na transição `<100 → 100` observada pelo cliente,
  independentemente da origem, e é suprimido por `prefers-reduced-motion`.
- **Densidade vs. luva.** Seis colunas no desktop e 40px de alvo no mobile são metas
  em tensão. Assumimos: no desktop a densidade vence; no mobile o alvo vence e a
  informação empilha. Não haverá um layout intermediário "tablet compacto" nesta
  rodada.

## Ficou de fora (priorização declarada)

- Virtualização da lista (`react-window`): desnecessária na cardinalidade real;
  reavaliar com o dataset de carga.
- Seleção múltipla de tarefas e ações em lote (não está em `§3.5`).
- Filtro por responsável ou por categoria dentro da tela (`§3.5` tem só os três
  segmentos; `my-tasks-view` cobre o corte por pessoa).
- Reordenação por drag & drop das tarefas dentro do robô.

## Plano de migração

Não há migração de dados nesta capacidade — ela não cria tabela de domínio. As duas
migrations possíveis são **aditivas e não destrutivas**:

1. Índice `(task_id, recorded_at DESC)` em `task_advances`, criado
   `CONCURRENTLY` (`disable_ddl_transaction!`) **apenas se** `progress-advances` não
   o tiver criado — a tarefa verifica antes.
2. Nenhuma coluna nova, nenhuma remoção. Não há necessidade de backup prévio.

O rollback é `drop_index`; a tela continua funcionando, mais lenta.

## Perguntas em aberto

1. Desnormalizar `advances_count`/`last_advance_id` em `tasks` com trigger — decidir
   depois que `progress-rollup` publicar os números do job de reconciliação (D5).
   Dono da decisão futura: `progress-rollup` + esta capacidade.
2. O pulso de 100% deve disparar também quando a tarefa chega a 100 por mudança de
   **status** para `Concluído` (`§2.2`), e não só por progresso? Assumimos **sim**
   (a transição observada é `<100 → 100` no valor consolidado da linha, qualquer que
   seja o gatilho). Confirmar com `progress-advances`.
3. Quando `§2.6` (sincronizar tarefas-base) adiciona tarefas, o filtro corrente deve
   ser resetado para "Todos" para que as novas apareçam? Assumimos **sim**, e há
   cenário para isso — mas não está literal em `§3.5`.
