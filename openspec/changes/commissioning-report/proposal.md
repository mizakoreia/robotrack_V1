## Why

A §3.8 da ESPECIFICACAO.md descreve o **único artefato formal** que o RoboTrack
produz: o *Protocolo de Comissionamento*. Não é uma tela de consulta — é o
documento que o cliente lê, confere contra o chão de fábrica e **assina no
aceite**. Todo o resto do sistema (hierarquia §1.1, avanços §2.4, trilha
append-only, timestamps de D8, log de auditoria §2.8) existe em parte para que
este papel seja defensável. Se o documento mostrar um número que não bate com a
tela, ou um horário que não bate com o que a pessoa fez, o valor jurídico e
comercial da assinatura cai junto.

Três armadilhas concretas, todas herdadas do legado:

1. **A métrica errada no carimbo.** O sistema tem duas métricas que coexistem de
   propósito (D15): ponderada (§2.1) e contagem crua (§3.2). A §3.8 é explícita —
   *"O percentual do carimbo é a média dos progressos ponderados dos projetos do
   escopo"*. É **média aritmética simples entre projetos, do número ponderado de
   cada projeto**. Trocar isso pela contagem crua dos hubs produz um documento que
   parece certo e está errado, e ninguém percebe até o cliente contestar.
2. **O timestamp errado no histórico.** Por **D8** existem `recorded_at` (quando a
   pessoa agiu, vem do cliente) e `created_at` (quando o servidor persistiu). Num
   protocolo assinado, um avanço feito às 14h no galpão sem sinal e sincronizado às
   17h **precisa constar como 14h** — é o horário do fato, não o da rede. O relatório
   exibe `recorded_at`, sempre e só.
3. **A autoria errada nas Conclusões.** Quem concluiu a tarefa é o **autor da entrada
   de histórico que chegou a 100**, não o responsável atual. Responsável muda depois;
   a trilha não. O responsável só entra como *fallback* quando não há entrada.

No legado isto era um `innerHTML` montado em JavaScript sobre documentos Firestore
já carregados inteiros no cliente, impresso com `window.print()`. O porte precisa
traduzir: **árvore aninhada → payload relacional único**, **cálculo no cliente →
agregado vindo de `progress-rollup`**, **`serverTimestamp()` → `recorded_at`**, e
**"imprime e reza" → layout A4 com contrato de paginação testado**.

Esta capacidade depende de `progress-rollup` (métrica ponderada por projeto,
§2.1/D5) e de `progress-advances` (trilha `task_advances` com `recorded_at`, D8).
Ela **não recalcula** nenhuma das duas coisas.

## What Changes

- **Endpoint único de leitura** `GET /api/v1/workspaces/:workspace_id/commissioning_report`
  com `scope=all` ou `scope=project&project_id=<uuid>`, servido por
  `Reports::CommissioningReportService` no contrato singleton do template
  (`ApiResponseHandler` → `{success:, data:, status:}`), representado por
  `Api::Entities::CommissioningReport`.
- **Payload autossuficiente e congelado**: um único JSON traz cabeçalho, carimbo,
  metadados (incluindo o id do documento já formatado), distribuição de status,
  a árvore projeto → célula → robô → tarefa → avanços, e a lista de Conclusões já
  resolvida (autoria + data). O cliente **não deriva nenhum número**: não soma
  status, não calcula média, não escolhe autor. Isso é o que permite que o
  documento seja reproduzível e que os testes de número sejam testes de backend.
- **Carimbo**: percentual = `round(avg(project.weighted_progress))` sobre os projetos
  do escopo, lido de `progress-rollup`. Rótulo `CONCLUÍDO` (=100) / `EM ANDAMENTO`
  (>0 e <100) / `PENDENTE` (=0). Escopo sem projeto nenhum → 0 / `PENDENTE`.
- **Id do documento** `RT-AAAAMMDD-HHMM`, gerado **no servidor** no fuso do workspace,
  congelado no payload e reusado idêntico no cabeçalho, nos metadados e no rodapé.
- **Distribuição de status** com os 4 glifos tipográficos `✓ ◐ ○ —`. São os **únicos
  glifos não-ícone do sistema**: §5.1 proíbe emoji em toda a UI, e esta é a exceção
  deliberada e fechada. O conjunto vive num módulo único, não espalhado em JSX.
- **Corpo hierárquico** com barra de progresso ponderada em cada nível (projeto,
  célula, robô), Aplicação do robô (§1.2), tabela de tarefas (símbolo, descrição,
  status, %, responsáveis) e, **abaixo de cada tarefa, suas entradas de histórico**
  (`recorded_at`, autor, `de→para`, comentário).
- **Seção "Conclusões"**: todas as tarefas a 100% do escopo, com quem concluiu
  (autor da última entrada que chegou a 100; fallback: responsáveis atuais; fallback
  final: traço) e quando (`recorded_at` dessa entrada).
- **Blocos de assinatura** "Comissionador" e "Cliente / Aceite", e **rodapé** com id,
  data de geração e nota de rastreabilidade.
- **Impressão A4 real**: folha de estilo de impressão dedicada com `@page`,
  cabeçalho/rodapé repetidos por página e garantia de que **uma tarefa nunca é
  separada do seu histórico** por quebra de página.
- **Orçamento de volume explícito** com truncamento **anunciado no próprio documento**
  quando o escopo excede o teto — nunca silencioso.
- **Todo texto fixo é format string versionada em locale** (D14): backend em
  `config/locales/pt-BR.report.yml` sob a chave `report.v1.*`, frontend no módulo
  único de strings. Um sweep de teste falha o CI se houver literal em português no
  componente do relatório.

### Não-objetivos

- **Não gera PDF no servidor.** A saída é HTML impresso pelo navegador (ver `design.md`).
- **Não persiste o documento emitido.** Não há tabela `commissioning_reports`, não há
  histórico de emissões, não há "reemitir o documento de terça". O id é carimbo
  temporal, não chave primária de nada.
- **Não implementa assinatura eletrônica.** Os blocos de assinatura são áreas em branco
  para caneta. Nada de certificado, hash ou ICP-Brasil.
- **Não envia o relatório por e-mail** e não expõe link público. Ver `workspace-invitations`
  e `delivery-and-observability` se isso virar requisito.
- **Não recalcula progresso.** Ponderado vem de `progress-rollup`; a contagem crua
  (§3.2) **não aparece neste documento** em nenhum lugar.
- **Não define a trilha de avanços.** `task_advances`, `recorded_at` e
  `author_name_snapshot` são de `progress-advances`.
- **Não cobre exportação de backup JSON** (é `workspace-settings` §3.11).
- **Não é offline-first.** Gerar o documento exige rede; o comportamento offline é
  uma mensagem honesta, não um cache. Ver `offline-pwa`.

### BREAKING

Nenhuma. Capacidade puramente aditiva e somente-leitura sobre o domínio existente.

## Capabilities

### New Capabilities

- `commissioning-report`: composição, autorização e semântica do Protocolo de
  Comissionamento — escopo, payload congelado, carimbo, id do documento,
  distribuição de status, corpo hierárquico com histórico por tarefa, Conclusões
  com resolução de autoria, assinaturas, rodapé e strings versionadas.
- `report-print-layout`: contrato de impressão A4 — página, margens,
  cabeçalho/rodapé repetidos, regras de quebra (tarefa + histórico indivisíveis),
  orçamento de volume e truncamento anunciado, e o conjunto fechado de glifos.

### Modified Capabilities

(nenhuma — `openspec/specs/` está vazio; nada foi construído ainda)

### Impact

- **Backend**: `app/services/reports/commissioning_report_service.rb`,
  `app/services/reports/document_id.rb`, `app/services/reports/completion_authorship.rb`,
  `app/api/entities/commissioning_report.rb` (sob `app/controllers/api/`, conforme o
  template), um endpoint montado em `api/v1/base.rb`, uma policy em `app/policies/`
  declarada explicitamente (D3), `config/locales/pt-BR.report.yml`.
- **Banco**: **nenhuma migration**. Leitura pura. Depende dos índices já criados por
  `progress-advances` (`task_advances(task_id, recorded_at)`) — se ele não existir,
  esta capacidade o exige como pré-requisito, não o cria por conta própria.
- **Frontend**: rota `/relatorio` no shell (`app-shell-navigation`), feature-folder
  `features/report/`, query key `['ws', wsId, 'report', scope]` (D9), folha
  `report-print.css` isolada, seletor de escopo.
- **Dependências declaradas**: `progress-rollup` (progresso ponderado por projeto e por
  nível, D5/D15), `progress-advances` (`task_advances`, `recorded_at`,
  `author_name_snapshot`, D8), `commissioning-hierarchy` (árvore e leitura tolerante),
  `robot-tasks` (status, peso, `task_assignees`), `workspace-tenancy` (RLS, D2),
  `authorization-policies` (D3), `design-system` (tokens, Inter, `tabular-nums`),
  `quality-and-accessibility` (D14, dataset de carga).
- **Entrega**: nenhuma env var nova, nenhuma fila, nenhum binário externo — que é
  exatamente o ponto da decisão de não gerar PDF server-side. Se ela for revertida,
  `delivery-and-observability` passa a precisar de Chromium na imagem e de uma fila
  dedicada; ver `design.md`.
