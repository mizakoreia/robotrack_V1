# end-to-end-testing

## ADDED Requirements

### Requirement: Harness Playwright com dois contextos de navegador

O sistema SHALL prover uma suíte E2E em `e2e/` baseada em `@playwright/test`,
capaz de instanciar **dois `BrowserContext` independentes e simultâneos** no mesmo
teste, cada um com seu `localStorage`, `sessionStorage`, cookies e conexão
ActionCable próprios (D-QA-1). A suíte SHALL rodar contra o **build de produção**
do frontend servido estaticamente, nunca contra `vite dev`.

#### Scenario: Duas sessões coexistem sem contaminação de token
- **WHEN** um teste abre `contextDono` autenticado como `dono@robotrack.test` e
  `contextConvidado` autenticado como `convidado@robotrack.test`
- **THEN** `contextDono.storageState()` e `contextConvidado.storageState()` SHALL
  conter JWTs diferentes, **E** uma requisição disparada em `contextConvidado`
  SHALL enviar o `Authorization` do convidado — nunca o do dono

#### Scenario: Service worker é registrado porque o build é o de produção
- **WHEN** a suíte sobe o alvo e a primeira página carrega
- **THEN** `context.serviceWorkers()` SHALL retornar exatamente 1 worker registrado
  — se retornar 0, a suíte SHALL falhar imediatamente com mensagem apontando que o
  alvo é `vite dev` e não o build servido, em vez de deixar o fluxo offline falhar
  por motivo obscuro

#### Scenario: Espera é por estado, nunca por tempo
- **WHEN** o lint da suíte varre `e2e/**/*.spec.ts`
- **THEN** SHALL falhar se encontrar `waitForTimeout`, `sleep` ou `setTimeout` como
  forma de sincronização — a única espera permitida é por localizador, resposta de
  rede ou evento

#### Scenario: Retry existe no CI e não existe localmente
- **WHEN** a suíte roda com `process.env.CI` ausente
- **THEN** `retries` SHALL ser `0` — um retry local esconde flake de quem está em
  posição de consertá-lo no mesmo minuto

### Requirement: Dataset E2E semeado pelo backend, com UUIDs literais

O sistema SHALL prover `bin/rails "rt:seed:e2e[cenario]"` que constrói o estado
inicial de cada fluxo com **UUIDs literais fixos** (D1 permite PK fornecida), sem
`Faker` e sem semente aleatória. A task SHALL ser idempotente: rodar duas vezes
SHALL produzir exatamente o mesmo estado (D-QA-2).

#### Scenario: Reexecução não duplica
- **WHEN** `rt:seed:e2e[relatorio]` é executada duas vezes seguidas
- **THEN** a contagem de `projects`, `cells`, `robots`, `tasks` e `task_advances`
  SHALL ser idêntica após a segunda execução, **E** nenhum registro SHALL ter id
  diferente do da primeira execução

#### Scenario: O teste cita o UUID que o seed criou
- **WHEN** o fluxo do relatório navega para o robô de referência
- **THEN** a URL SHALL conter o UUID literal declarado no seed (ex.:
  `00000000-0000-4000-8000-0000000000r1`), e não um id resolvido por busca de nome
  — resolver por nome esconde a criação de um registro duplicado

#### Scenario: Nenhum estado inicial é construído pela UI
- **WHEN** o lint da suíte inspeciona os passos anteriores ao primeiro `expect` de
  cada spec
- **THEN** SHALL falhar se houver mais de 6 interações de UI antes do primeiro
  assert — o preparo é do seed, a UI é o que está sob teste

### Requirement: Fluxo E2E de convite ponta a ponta entre dois usuários

O sistema SHALL cobrir com E2E o ciclo completo de §3.10: o dono cria o convite,
o convidado abre o link, autentica-se, aceita, e passa a enxergar o workspace com
o papel concedido — com as **duas sessões abertas simultaneamente**.

#### Scenario: Convite de editor concede escrita ao convidado
- **WHEN** o dono, em `contextDono`, convida `convidado@robotrack.test` com papel
  `edit`, e o convidado, em `contextConvidado`, abre o link do convite, autentica
  e aceita
- **THEN** o convidado SHALL ver `WS-CARGA` no seletor de workspace com badge de
  papel `Editor`, **E** SHALL conseguir registrar um avanço `+10` numa tarefa,
  **E** o painel de equipe do dono SHALL listar o convidado sem recarregar a página

#### Scenario: O mesmo link de convite não serve duas vezes
- **WHEN** um terceiro contexto abre o mesmo link já consumido
- **THEN** a tela SHALL exibir a mensagem de convite já utilizado vinda do catálogo
  pt-BR, **E** o terceiro usuário SHALL continuar sem acesso a `WS-CARGA` — o
  seletor de workspace dele SHALL não listar `WS-CARGA`

#### Scenario: Convite de leitor não concede escrita
- **WHEN** o convite é emitido com papel `view` e aceito
- **THEN** o convidado SHALL ver a tarefa mas o controle de status SHALL estar
  desabilitado, **E** um `PATCH` forjado a partir do console do convidado SHALL
  retornar `403` — a negação SHALL existir no servidor, não só na UI

#### Scenario: Token de convite sobrevive ao redirect do Google
- **WHEN** o convidado abre o link de convite sem sessão e escolhe entrar com
  Google (D4 — redirect, não popup)
- **THEN** após o retorno do provedor a tela de aceite SHALL estar carregada com o
  mesmo token, **E** não SHALL exigir que o convidado reabra o e-mail

### Requirement: Fluxo E2E de avanço offline com sincronização

O sistema SHALL cobrir com E2E o registro de avanço com a rede **realmente
desligada** (`context.setOffline(true)`) e a drenagem da fila IndexedDB ao
reconectar (§4.2, §4.3, D7).

#### Scenario: Avanço registrado offline aparece otimista e é marcado como pendente
- **WHEN** a rede é desligada e o usuário registra `+10` numa tarefa que estava em
  40
- **THEN** a tabela SHALL exibir `50`, **E** o indicador de gravação SHALL exibir o
  estado pendente/offline — nunca `salvo`, que seria desonestidade de estado
  (`PRODUCT.md §Design Principles`)

#### Scenario: A fila drena na ordem e o servidor converge
- **WHEN** três avanços são registrados offline em tarefas distintas e a rede é
  religada
- **THEN** o servidor SHALL ter exatamente 3 `task_advances` novos, **E** o
  `recorded_at` de cada um SHALL ser o instante em que a pessoa agiu (D8), anterior
  ao respectivo `created_at`, **E** o indicador SHALL transitar para `salvo`

#### Scenario: Recarregar a página com a fila cheia não perde avanço
- **WHEN** dois avanços estão na fila IndexedDB, a página é recarregada ainda
  offline, e só então a rede volta
- **THEN** os dois avanços SHALL ser enviados após o recarregamento — a fila SHALL
  sobreviver ao ciclo de vida da aba, senão o operário perde trabalho ao trocar de
  app no celular

#### Scenario: Dependência entre itens da fila é respeitada
- **WHEN** offline o usuário cria um robô novo e registra um avanço numa tarefa
  desse robô, e a rede volta
- **THEN** o robô SHALL ser criado antes do avanço, **E** o avanço SHALL persistir
  com sucesso — inverter a ordem produziria `404` no avanço e um item envenenado
  na fila

### Requirement: Fluxo E2E de troca de workspace sem vazamento

O sistema SHALL cobrir com E2E a troca de workspace afirmando ausência de dados do
tenant oposto **no DOM e nos corpos de resposta capturados**, por comparação de
**texto literal distintivo**, não de id (D-QA-9).

#### Scenario: Nome do tenant oposto não aparece no DOM
- **WHEN** o usuário está em `WS-CARGA` e navega por Visão Geral, Projeto, Célula,
  Robô e Minhas Tarefas
- **THEN** o `innerText` do documento SHALL não conter a substring `ISCA-` em
  nenhuma das cinco telas

#### Scenario: Cache de React Query não pisca dado antigo após a troca
- **WHEN** o usuário troca de `WS-CARGA` para `WS-ISCA` e a Visão Geral renderiza
- **THEN** em nenhum quadro entre a troca e o primeiro render SHALL aparecer um
  nome de projeto de `WS-CARGA` — a asserção SHALL cobrir o intervalo, não só o
  estado final, porque o piscar de 300 ms é exatamente o bug que a troca descartando
  estado (D9) existe para prevenir

#### Scenario: Nenhuma resposta de rede carrega o workspace oposto
- **WHEN** todas as respostas JSON da sessão em `WS-ISCA` são capturadas
- **THEN** nenhuma SHALL conter o UUID de `WS-CARGA` nem a substring `CARGA-`

#### Scenario: URL profunda do outro tenant não abre
- **WHEN** o usuário, em `WS-ISCA`, cola na barra de endereço a URL de um robô de
  `WS-CARGA` ao qual ele não tem acesso
- **THEN** a tela SHALL exibir o estado de recurso não encontrado, **E** a resposta
  da API SHALL ser `404` com corpo que não contém o nome do robô — `403` com o nome
  no corpo já seria vazamento

### Requirement: Fluxo E2E de revogação de acesso ao vivo

O sistema SHALL cobrir com E2E a revogação de membership enquanto a sessão alvo
está aberta, com as duas sessões simultâneas e propagação por `WorkspaceChannel`
(§3.10, D6).

#### Scenario: Revogação expulsa a sessão aberta sem recarregamento manual
- **WHEN** o dono, em `contextDono`, remove o acesso do convidado, enquanto
  `contextConvidado` está com a tela de Robô aberta
- **THEN** em até 5 segundos `contextConvidado` SHALL sair de `WS-CARGA` e exibir a
  mensagem de perda de acesso vinda do catálogo pt-BR, **E** o anúncio SHALL ir
  para a região `aria-live="assertive"` (D-QA-4)

#### Scenario: Escrita em voo depois da revogação é negada pelo servidor
- **WHEN** o convidado tem o modal de avanço aberto no instante da revogação e
  confirma o `+10` logo depois
- **THEN** a API SHALL responder `403`, **E** nenhum `task_advance` SHALL ser
  criado, **E** a UI SHALL reverter o valor otimista para o original

#### Scenario: A revogação não derruba a outra sessão do dono
- **WHEN** a revogação ocorre
- **THEN** `contextDono` SHALL continuar operante em `WS-CARGA` — a mensagem do
  canal SHALL ser endereçada, não um broadcast que desloga todo mundo

### Requirement: Fluxo E2E do relatório A4 sobre dataset conhecido

O sistema SHALL cobrir com E2E a geração do relatório de comissionamento (§3.8)
sobre um dataset semeado cujos números são **literais no teste**, incluindo o caso
em que as duas métricas de progresso divergem (D15).

#### Scenario: Os números do relatório batem com o dataset literal
- **WHEN** o relatório é gerado no escopo do projeto `PRJ-REL` do cenário
  `rt:seed:e2e[relatorio]`, que tem 2 células, 4 robôs e 40 tarefas — 18
  `Concluído`, 9 `Em Andamento`, 11 `Pendente`, 2 `N/A`
- **THEN** a distribuição de status impressa SHALL ser exatamente `18 / 9 / 11 / 2`,
  **E** o total SHALL ser `40`

#### Scenario: As duas métricas divergem e ambas são rotuladas
- **WHEN** o mesmo dataset produz progresso ponderado `62%` e contagem crua
  `18/40 = 45%`
- **THEN** o documento SHALL exibir os dois números com rótulo explícito de qual
  métrica é cada um — um relatório que exibe `62%` sem dizer "ponderado" ao lado de
  `45%` sem dizer "contagem" é indefensável na frente do cliente que assina

#### Scenario: O identificador do relatório segue o formato e o carimbo
- **WHEN** o relatório é gerado em `2026-03-14T09:07` no fuso do workspace
- **THEN** o identificador impresso SHALL casar exatamente com
  `RT-20260314-0907`

#### Scenario: Robô sem tarefas não some do corpo hierárquico
- **WHEN** o dataset inclui `ROB-VAZIO`, um robô sem nenhuma tarefa
- **THEN** ele SHALL aparecer no corpo hierárquico com progresso `0%` e a indicação
  de ausência de tarefas — omiti-lo faria o cliente assinar um documento que não
  menciona um robô do escopo

#### Scenario: O documento cabe na paginação A4 esperada
- **WHEN** o relatório é impresso para PDF em A4 retrato
- **THEN** SHALL ter exatamente 3 páginas para este dataset, **E** o bloco de
  assinaturas SHALL estar na última página, não órfão numa quarta

### Requirement: Fixtures multi-tenant de request compartilhadas

O sistema SHALL estender a base de teste de `seal-template-baseline` com factories
de domínio RoboTrack e um helper de request `as_member_of(workspace, role:)` que
abre o contexto de tenant (D2) e autentica em um único passo, eliminando a
redefinição de `bearer_for` por spec.

#### Scenario: Helper abre o contexto de tenant junto com a autenticação
- **WHEN** um request spec usa `as_member_of(ws_a, role: :edit)` e faz `GET
  /api/v1/projects`
- **THEN** `current_setting('app.current_workspace_id')` SHALL ser o id de `ws_a`
  durante a requisição — autenticar sem abrir o contexto de RLS produziria uma
  lista vazia e um teste que "passa" por engano

#### Scenario: Trocar de membership no mesmo exemplo não vaza contexto
- **WHEN** um spec usa `as_member_of(ws_a)` e depois `as_member_of(ws_b)` no mesmo
  exemplo
- **THEN** a segunda requisição SHALL enxergar apenas dados de `ws_b`

#### Scenario: Factory de tarefa resolve o workspace pela hierarquia
- **WHEN** `create(:task)` é chamada sem informar `workspace_id`
- **THEN** a tarefa SHALL nascer com o `workspace_id` do robô pai — uma factory que
  exige o campo explicitamente faz cada spec repetir a resolução e errar em um deles

### Requirement: Guarda contra suíte de frontend importando páginas inexistentes

O sistema SHALL manter um guarda de CI que reprova qualquer arquivo de teste do
frontend que importe módulo inexistente, impedindo a reintrodução da dívida do
template.

#### Scenario: Import quebrado em teste reprova o CI
- **WHEN** um teste importa `../pages/CheckoutPage` e o arquivo não existe
- **THEN** o passo de type-check da suíte SHALL falhar nomeando o arquivo de teste
  e o módulo ausente, **E** SHALL falhar antes da execução dos testes — não como um
  erro de runtime dentro de um `describe` que alguém marca como `skip`
