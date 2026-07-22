# Tarefas — robot-task-table

## Nota de paralelismo (leia antes de distribuir)

O plano anterior tratava esta tela como uma cadeia linear de 7 tarefas sequenciais, o
que impedia dividi-la entre pessoas. É falso: dado o **esqueleto** do Grupo 1
(contrato `TaskRow`, endpoint agregado, rota, layout de grupo/linha), as trilhas
**3, 4, 5 e 6** consomem campos disjuntos do mesmo objeto e **não compartilham
estado** — podem ser executadas em paralelo por pessoas diferentes.

```
Grupo 1 (sequencial, bloqueante)  →  ┌ Grupo 2  colunas de mutação  (Status, Progresso)
                                     ├ Grupo 3  colunas de leitura  (Responsáveis, Trilha, avisos)
                                     ├ Grupo 4  ações + cabeçalho
                                     ├ Grupo 5  modais (histórico · atribuição)
                                     └ Grupo 6  mobile + a11y + pulso
                                                        ↓
                                              Grupo 7 (integração)
```

Única aresta extra: **5.3** (modal de atribuição) e **3.1** (chips) tocam o mesmo
componente de célula — quem chegar depois consome a interface já publicada em 1.3.

---

## 1. Esqueleto e contrato de dados (bloqueante — faça primeiro, em ordem)

- [x] 1.1 Criar `Api::Entities::TaskRow` expondo `id, category, description, weight,
  progress, status, lock_version, assignees[{person_id,name}],
  contributors[{person_id,name}], advances_count,
  last_advance{comment,recorded_at,author_name_snapshot,legacy}` (§3.5 — spec de
  contrato falha se `recorded_at` for trocado por `created_at` ou se `contributors`
  vier mesclado em `assignees`)
- [x] 1.2 Implementar `RobotTasksService.list` com os dois `LEFT JOIN LATERAL` sobre
  `task_advances` (contagem/contribuidores e último avanço por
  `recorded_at DESC, created_at DESC`), e montar `GET /api/v1/robots/:id/tasks` em
  `api/v1/base.rb` declarando a policy de leitura (D3) (§3.5 — robô com 40 tarefas e
  200 avanços resolve em ≤3 queries totais; teste conta queries e falha em N+1)
- [x] 1.3 Criar `frontend/src/features/robot-tasks/` com os tipos gerados do contrato,
  o hook `useRobotTasks` na query key `['ws', wsId, 'robot', robotId, 'tasks']` (D9) e
  a interface pública dos componentes de célula (§3.5, D-RTT-10 — nenhuma célula
  importa `apiClient` diretamente; o padrão `useEffect + apiClient` do template não se
  propaga)
- [x] 1.4 Montar a rota da tela do robô com `key={robotId}`, o layout de grupo por
  categoria com linha separadora, e os estados de carregamento/vazio/erro (§3.5, §2.9
  — robô sem tarefas mostra estado vazio nomeando o robô, não uma tabela de 0 linhas;
  falha 500 mostra erro com nova tentativa, não estado vazio)
- [x] 1.5 Implementar o `robotTaskFilterStore` (Zustand, sem `persist`) e o controle
  segmentado, com reset por `useEffect([robotId])` **e** pelo `key` da rota (§3.5,
  D-RTT-1 — sair do robô A para o B e voltar ao A mostra "Todos", não o filtro
  anterior; nada de filtro na URL)
- [x] 1.6 **Verificação:** teste de request do endpoint agregado (contagem de queries,
  contrato, 404 para robô de outro workspace via RLS) + teste de componente do reset
  de filtro nos três caminhos de navegação (§3.5, §4.1 inv. 1 — robô de W2 pedido por
  usuário de W1 devolve 404 sem vazar nome)

## 2. Colunas de mutação — Status e Progresso (paralelo)

- [x] 2.1 Implementar a célula de Status com o `StatusSelect` do `design-system`
  (chevron obrigatório) e as 4 opções, disparando a abertura do modal de avanço de
  `progress-advances` com o `para%` derivado de §2.2 (§3.5, §2.2 — escolher
  `Concluído` numa tarefa de progresso 60 abre o modal com `60 → 100`; a pílula só
  muda depois de confirmar)
- [x] 2.2 Implementar a célula de Progresso: leitura `%` com `tabular-nums`, `−`,
  slider passo 5 e `+`, com `persisted` vindo sempre da query e `draft` local
  descartável (§2.4, D-RTT-5 — dois `+` seguidos sem recarregar produzem +20, não
  +10; o segundo modal abre com `30 → 40`)
- [x] 2.3 Ligar o resultado do modal (confirmar/cancelar/erro 409) ao estado da célula
  e à invalidação de `['ws',wsId,'robot',robotId,'tasks']` e `['ws',wsId,'projects']`
  (§2.4 item 5, D5 — arrastar de 30 para 70 e cancelar devolve o slider a 30 e não
  envia nenhuma requisição; 409 de `lock_version` recarrega e reabre com o valor novo)
- [x] 2.4 **Verificação:** testes de componente para incremento duplo, cancelamento,
  conflito 409 e para o status devolvido pelo servidor sobrepondo o rascunho (§2.2,
  §2.4 — confirmar `para 100` exibe `Concluído` mesmo que o usuário tenha escolhido
  outro status antes)

## 3. Colunas de leitura e avisos — Responsáveis e Trilha (paralelo)

- [x] 3.1 Implementar a célula Responsáveis com chips primários (`assignees`) e
  secundários (`contributors` menos a intersecção), abrindo o modal de atribuição no
  clique (§3.5, D-RTT-4 — `assignees=[Ana]` com avanço de Bruno mostra `Ana` primário
  e `Bruno` secundário; `assignees=[Ana]` com avanço de Ana mostra um único chip)
- [x] 3.2 Implementar a célula Trilha com o comentário de `last_advance` e o botão de
  contagem com `aria-label` informando o número de entradas (§3.5 — tarefa com 3
  avanços exibe o comentário do mais recente por `recorded_at`, não o de maior
  `created_at`)
- [x] 3.3 Implementar o aviso "Atribuir…" com ícone de alerta, condicionado a
  `progress > 0 AND assignees = []`, não bloqueante (§3.5 — progresso 30 sem
  responsável mostra o aviso; progresso 0 sem responsável **não** mostra; progresso 45
  com contribuidor Bruno e zero responsáveis mostra aviso **e** chip secundário)
- [x] 3.4 Implementar o aviso "Registre o avanço…" condicionado a
  `0 < progress < 100 AND advances_count = 0`, com a cláusula "nem nota" removida e a
  remoção comentada no código apontando para D-RTT-6 (§3.5, §1.4, D8 — tarefa migrada
  com `obs` convertida em avanço `legacy` tem `advances_count = 1` e **não** mostra o
  aviso; progresso 100 sem avanços também não)
- [x] 3.5 **Verificação:** teste de matriz dos dois avisos cobrindo os 6 pares
  (progresso 0/30/100 × com/sem responsável, e 0/50/100 × com/sem avanço) (§3.5 — a
  matriz falha se alguém reintroduzir `obs` ou trocar `>` por `>=` na condição)

## 4. Cabeçalho e coluna Ações (paralelo)

- [x] 4.1 Implementar o cabeçalho com nome, badge de Aplicação e percentual
  **ponderado rotulado** vindo de `progress-rollup` (§2.1, D15 — robô com progressos
  `100,50,0,0` peso 1 exibe `38%` com o rótulo `Progresso ponderado`; robô só com
  `N/A` exibe `100%`, não `0%`)
- [x] 4.2 Ligar a ação "Sincronizar tarefas-base" ao endpoint de `task-catalog`,
  exibindo a contagem retornada e resetando o filtro para `Todos` (§2.6 — resposta de
  7 adicionadas exibe `7 tarefas adicionadas` e as novas linhas ficam visíveis mesmo
  que o filtro estivesse em `Concluídos`)
- [x] 4.3 Implementar a coluna Ações: editar descrição e excluir tarefa, com diálogo
  de confirmação na exclusão, consumindo o CRUD de `robot-tasks` (§3.5 — excluir uma
  tarefa de peso 1 recalcula o percentual do cabeçalho na mesma render, sem F5)
- [x] 4.4 Aplicar as restrições de papel na tela: para `view`, remover do DOM
  "Adicionar tarefa", "Sincronizar", coluna Ações, slider e `±`, e renderizar o status
  como `Badge` estático (§4.1, D-RTT-9 — membro `view` não vê select desabilitado nem
  alvo morto; badge sem chevron)
- [x] 4.5 **Verificação:** specs de request confirmando `403` para `view` em
  `PATCH /tasks/:id`, `DELETE /tasks/:id` e no endpoint de sincronização, e teste de
  render confirmando ausência dos controles (§4.1 inv. 1 e 4 — bloqueio na UI é
  conveniência; a prova é o 403)

## 5. Modais de colaboração (paralelo)

- [x] 5.1 Implementar o modal de histórico: lista de contribuidores distinta +
  timeline ordenada por `recorded_at DESC, created_at DESC`, exibindo autor,
  `de% → para%`, data/hora e comentário (§3.5, D8 — avanço com
  `recorded_at 14:05` / `created_at 18:40` exibe `14:05`; dois `recorded_at` iguais
  mantêm a mesma ordem entre recarregamentos)
- [x] 5.2 Marcar entradas `legacy` na timeline e tratar avanço de `→100` sem
  comentário com marcador explícito de ausência (§3.5, §2.4 item 3 — entrada sem
  comentário não herda visualmente o comentário da entrada vizinha)
- [x] 5.3 Implementar o modal de atribuição: checkboxes de todas as `people` do
  workspace com os atuais marcados, salvando via
  `PUT /api/v1/tasks/:id/assignees` com policy declarada (§3.5, D11 — desmarcar todos
  deixa `assignees` vazio e **não** cria pessoa `"Não Atribuído"`)
- [x] 5.4 Implementar o cadastro de pessoa nova no modal, delegando a criação de
  `Person` a `workspace-tenancy`, com a pessoa entrando já marcada (§3.5, D10 —
  digitar `  ana  ` com `Ana` já existente marca a existente e informa duplicidade,
  em vez de criar uma segunda; campo em branco é rejeitado)
- [x] 5.5 **Verificação:** testes de componente dos dois modais (ordem da timeline,
  marcador legado, dedup de nome, seleção vazia) + spec de request de `403` para
  `view` em `PUT /tasks/:id/assignees` e de que a lista não inclui pessoa de outro
  workspace (§4.1, D2 — usuário de W1 não vê `Eduardo` de W2)

## 6. Mobile, movimento e acessibilidade (paralelo)

- [x] 6.1 Implementar o refluxo em cartões abaixo do breakpoint `md`, preservando as
  seis informações e os cabeçalhos de categoria como separadores de seção (§3.5,
  D-RTT-8 — em 375px o documento não rola horizontalmente e Ações/Trilha continuam
  visíveis sem scroll lateral)
- [x] 6.2 Dimensionar alvos de toque (≥40px em `−`, `+`, editar, excluir e linhas de
  checkbox; ≥32px piso geral) e aplicar `touch-action: pan-y` ao slider (PRODUCT.md,
  DESIGN.md — arrastar o dedo verticalmente sobre o slider rola a página em vez de
  mudar o progresso)
- [x] 6.3 Implementar o `successPulse` na transição `<100 → 100` da linha, disparado
  uma única vez e suprimido por `prefers-reduced-motion` (§3.5, DESIGN.md §Motion —
  avanço de `90 → 100` pulsa uma vez; com movimento reduzido não anima mas atualiza
  para `Concluído`)
- [x] 6.4 Aplicar ARIA da tela: `role="progressbar"` nas leituras, `aria-label` nos
  botões só-ícone, foco preso e `Esc` devolvendo foco ao gatilho nos dois modais
  (DESIGN.md §Accessibility — `Esc` no modal de histórico devolve o foco ao botão de
  contagem **da mesma linha**, não ao topo da tabela)
- [x] 6.5 **Verificação:** teste de a11y automatizado nos dois temas em 375px e
  1280px, com asserção de tamanho de alvo e de contraste das 3 variantes de cor de
  status (§5.1 — trocar variante de cor de status quebra AA e o teste acusa)

## 7. Integração e prova de ponta a ponta

- [ ] 7.1 Integrar as trilhas 2–6 na tela e resolver os conflitos de célula
  (Responsáveis compartilhada entre 3.1 e 5.3), garantindo render única por mutação
  (§3.5 — confirmar um avanço não remonta a tabela inteira; medido por contador de
  render nas linhas não afetadas)
- [ ] 7.2 Escrever o E2E dos cenários operacionais: reset de filtro em A→B→A, aviso
  "Atribuir…" em progresso 30 sem responsável, cancelamento de slider, contribuidor
  não-responsável como chip secundário, e membro `view` sem ações (§3.5, §4.1 — cada
  cenário nomeado é um teste; a suíte falha se o filtro persistir entre navegações)
- [ ] 7.3 **Verificação:** rodar a tela contra o dataset de carga (robô com 40
  tarefas em 9 categorias e 200 avanços) medindo tempo até interativo e número de
  requisições (§3.5, D-RTT-3 — uma requisição carrega a tabela inteira; qualquer
  requisição por linha reprova)
