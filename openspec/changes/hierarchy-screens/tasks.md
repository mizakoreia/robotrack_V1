# tasks — hierarchy-screens

## 1. Fixtures e contrato das duas métricas

- [x] 1.1 Criar a factory/fixture `divergent_progress` em `backend/spec/factories/`:
  workspace com 1 projeto → 1 célula → 1 robô → 4 tarefas (peso 5 em `Concluído`/100%;
  três de peso 1 em `Pendente`/0%). (§2.1 + §3.2 — a fixture SHALL produzir ponderado 40 e
  contagem crua 25; se um seed uniforme fizer os dois valores coincidirem, ela não serve
  para o teste de D15 e a tarefa está incompleta)
- [x] 1.2 Definir as entities `Api::Entities::HierarchyCard` e `Api::Entities::AnalyticsHub`
  expondo `weighted_progress` (inteiro) e `raw_completion` (`{completed, total, percent}`),
  sem nenhum campo `progress`. (§3.2 — um cliente que peça `progress` recebe `nil`, não o
  ponderado disfarçado)
- [x] 1.3 Escrever o spec de contrato que percorre a resposta dos 4 endpoints em busca da
  chave `progress` em qualquer profundidade e falha se encontrar. (D15 — o teste falha se
  alguém adicionar um alias `progress` "por conveniência do front")

## 2. Endpoints agregados de leitura

- [x] 2.1 `Hierarchy::OverviewService` + `GET /api/v1/workspaces/:id/overview`: contagens
  globais, agregado de tarefas e lista de projetos com `progress_cache` e contagem de
  células. (§3.2 — workspace com 0 tarefas devolve `percent: 0`, não `NaN` nem divisão por
  zero)
- [x] 2.2 `Hierarchy::ProjectOverviewService` + `GET /api/v1/projects/:id/overview`: hub do
  projeto e cards de célula com `robots_count`. (§3.3 — projeto sem células devolve
  `cells: []` e hub zerado, não 404)
- [x] 2.3 `Hierarchy::CellOverviewService` + `GET /api/v1/cells/:id/overview`: hub da célula
  e cards de robô com `application` e `tasks_count`. (§3.4 — robô com 3 tarefas todas `N/A`
  devolve `weighted_progress: 100` e `raw_completion.completed: 0`)
- [x] 2.4 Declarar a policy de leitura de cada um dos 3 endpoints e montá-los em
  `api/v1/base.rb`. (§4.1 inv. 1 — o route-sweep spec de `authorization-policies` falha se
  algum destes endpoints subir sem policy declarada)
- [x] 2.5 Spec de request de isolamento: pessoa de `W1` pedindo `overview` de projeto de
  `W2` recebe 404. (§4.1 — o corpo da resposta não pode conter o nome do projeto de `W2`
  nem em mensagem de erro)
- [x] 2.6 Spec contador de queries sobre dataset de 20 projetos × 5 células × 8 robôs,
  falhando acima de 3 queries por request. (design D-C — 20 projetos SHALL custar o mesmo
  número de queries que 1 projeto; um `map` com `cells.count` dentro reintroduz N+1 sem
  mudar a resposta)

## 3. Endpoint de busca

- [x] 3.1 `Hierarchy::SearchService` + `GET /api/v1/workspaces/:id/search?q=`: `ILIKE` sobre
  `projects.name`, `cells.name`, `robots.name`, ordenado projeto → célula → robô e por nome.
  O termo é escapado para `%`, `_` e `\` antes do `ILIKE`. (§3.7 — buscar `sol` retorna
  "Solda 01" e "R02 - Solda" e NÃO retorna a tarefa "Solda MIG"; buscar `%` num workspace
  com 12 itens retorna 0 resultados, não os 12)
- [x] 3.2 Montar `path_label` no servidor com format string versionada em
  `config/locales/pt-BR.hierarchy.yml`. (D14 + §3.7 — robô devolve `"Robô · em Solda 01 ·
  Linha 300"`; um robô órfão de célula não pode gerar `"Robô · em  · "`)
- [x] 3.3 Spec de request negativo: busca em workspace onde a pessoa não é membro responde
  403/404 e nomes homônimos de outro tenant não aparecem no contador. (§4.1 — `W1` buscando
  `solda` com "Solda 99" em `W2` devolve count 1)

## 4. Tela Visão Geral

- [x] 4.1 Hook `useWorkspaceOverview` com a key `['ws', wsId, 'overview']` e tipos TS sem
  campo genérico de progresso. (D9 — trocar `weightedProgress` por `rawCompletion` na
  chamada do anel SHALL virar erro de compilação, não bug silencioso)
- [x] 4.2 Compor o hub global com o `HubBar` de `design-system`, rotulado "de progresso
  físico global". (§3.2 — 10 de 40 tarefas exibe "10/40" e "25%", nunca o ponderado)
- [x] 4.3 Compor a grade de cards de Projeto (ícone, nome, badge em linha própria, anel
  ponderado, rodapé "Visão macro / Acessar"). (§5.2 — projetos de nome curto e de 60 chars
  na mesma linha mantêm os anéis alinhados e altura de card igual)
- [x] 4.4 Estado vazio da Visão Geral com CTA "Novo Projeto", e variante sem CTA para papel
  `view`. (§3.2 + §4.1 — leitor abre workspace vazio e não vê nenhum botão de criação)
- [x] 4.5 Estados de carregamento (esqueleto no gabarito do hub+grade) e de erro com
  "Tentar novamente". (§3.2 — resposta 500 exibe erro, não o estado vazio "Novo Projeto";
  a chegada dos dados não desloca o layout)
- [x] 4.6 Teste de componente sobre a fixture divergente: hub mostra "1/4" e "25% de
  progresso físico global" **e** o anel mostra 40% com `aria-label` "Progresso ponderado:
  40%". (D15 — se alguém unificar as métricas os dois viram o mesmo número e o teste quebra)

## 5. Telas Projeto e Célula

- [x] 5.1 Página de Projeto: hub (Células configuradas · Robôs analisados · Tarefas
  concluídas) + grade de cards de Célula com badge `N robô(s)` e rodapé "Status global /
  Acessar". (§3.3 — célula com 4 robôs e 55% exibe badge "4 robôs" e anel 55%)
- [x] 5.2 Ligar as ações nova célula, renomear e excluir célula aos fluxos de
  `commissioning-hierarchy`, invalidando `['ws', wsId, 'project', id, 'overview']`.
  (§3.3 — excluir 1 de 2 células atualiza grade e hub para "Células configuradas 1" sem
  recarregar a página)
- [x] 5.3 Página de Célula: hub (Robôs configurados · Tarefas concluídas) + grade de cards
  de Robô com badge = Aplicação e rodapé `N tarefas`. (§3.4 — badge exibe a Aplicação e não
  a contagem de tarefas; badge não pode ter afordância de seletor, §5.2)
- [x] 5.4 Ligar "adicionar robô(s)" ao assistente de `robot-tasks` e "Abrir" à rota do robô.
  (§3.4 — "Abrir" no card do robô `r-9` navega para a tabela de tarefas de `r-9`)
- [x] 5.5 Estados vazios de nível: projeto sem célula e célula sem robô, com o CTA do nível
  e variante sem ação para `view`. (§3.3/§3.4 — o texto não pode ser o mesmo "nada aqui" da
  Visão Geral; cada estado nomeia a ação daquele nível)
- [x] 5.6 Teste E2E do caminho Visão Geral → Projeto → Célula → Robô e do botão voltar.
  (§3.2–§3.4 — voltar da célula retorna ao projeto de origem, não à Visão Geral)

## 6. Busca na UI

- [x] 6.1 Componente `HierarchySearchField`: `<form role="search">` + `<input type="search"
  enterKeyHint="search" inputMode="search">` + botão `type="submit"` + botão limpar.
  (§3.7 — a tecla "buscar" do teclado mobile dispara `submit`; um handler só de `keydown`
  de Enter não a captura em iOS/Android)
- [x] 6.2 Hook `useHierarchySearch` com debounce de 250 ms, key `['ws', wsId, 'search', q]`
  e `keepPreviousData`; `submit` faz flush do debounce. (§3.7 — Enter logo após digitar
  executa uma busca, não duas)
- [x] 6.3 Substituição da visão derivada de `debouncedQuery.trim().length > 0`, sem flag
  booleana separada. (§3.7 — digitar `sol` esconde hub e grade; limpar restaura os mesmos
  números do hub sem recarregar a página)
- [x] 6.4 Lista plana de resultados com ícone do tipo, nome, `path_label` e navegação ao
  destino, mais o contador e o estado vazio nomeando o termo com botão limpar. (§3.7 —
  clicar no resultado da célula `c-7` abre a tela de `c-7`, não a do projeto pai; buscar
  `xyz` exibe literalmente `xyz` na mensagem, um "nenhum resultado" genérico não atende)
- [x] 6.5 Teste de integração da busca: `sol` acha "Solda 01" e "R02 - Solda" e não acha a
  tarefa "Solda MIG"; `xyz` mostra o vazio com o termo; limpar restaura hub e grade.
  (§3.7 — os três casos no mesmo teste; se a busca varrer tarefas, o primeiro caso falha)

## 7. Acessibilidade, responsivo e verificação final

- [ ] 7.1 Refluxo mobile: grade em coluna única abaixo de 640px, alvos de toque ≥ 32px,
  campo de busca sem zoom no foco (fonte ≥ 16px). (PRODUCT.md/§5.1 — uso com luva; um botão
  de 24px na grade reprova)
- [ ] 7.2 `aria-live="polite"` no contador de resultados e foco preservado no campo após a
  busca. (§3.7 + §5.1 — leitor de tela anuncia "3 resultados" sem o foco pular para a lista)
- [ ] 7.3 Auditoria de contraste AA das três telas nos dois temas, incluindo anel a 0% e
  badges de status. (§5.1 — a variante "tinta" usada como fundo sólido reprova o AA; medir,
  não assumir)
- [ ] 7.4 Verificação final: rodar a suíte destas telas sobre a fixture `divergent_progress`
  + o contador de queries + o E2E de navegação e busca, e registrar os números medidos.
  (D15 e design D-C — a prova é ponderado 40 ≠ crua 25 exibidos e rotulados na mesma tela, e
  ≤ 3 queries por endpoint com 20 projetos)
