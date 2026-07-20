## Context

§3.8 é o único lugar do RoboTrack onde o software produz um artefato que sai do
software: uma folha A4 assinada por duas partes. Isso muda o critério de qualidade.
Numa tela, um número errado é um bug que se corrige no próximo deploy; num protocolo
assinado, é uma divergência entre o que o cliente aceitou e o que foi entregue.

O legado montava o documento em JavaScript sobre a árvore Firestore inteira já
carregada no cliente e chamava `window.print()`. Duas consequências herdadas que o
porte precisa desfazer conscientemente:

- **Os números eram recalculados no cliente a cada render.** No porte, o cliente que
  recalcula é o cliente que diverge do resto da UI — a métrica ponderada vive em
  `progress-rollup` (D5) e o relatório a **consome**, não a reimplementa.
- **A paginação era o que o navegador quisesse fazer.** Um robô com 25 tarefas, cada
  uma com 6 entradas de histórico, quebrava no meio de uma tarefa e o histórico caía
  na página seguinte sem contexto. Num documento de aceite, isso não é feio — é
  ambíguo.

Escopo do documento: `todos os projetos` ou `um projeto`. Volume real de um workspace
de porte: ~8 projetos × ~6 células × ~5 robôs × ~31 tarefas ≈ **7.400 tarefas** e,
com 2–4 avanços por tarefa concluída, na casa das **dezenas de milhares de linhas de
histórico**. Um documento de 800 páginas não é um documento — é um travamento do
navegador. Isso não é hipótese: é o escopo `all` de um workspace grande.

O plano anterior modelou esta capacidade como **cadeia linear de 7 tarefas
sequenciais** (cabeçalho → metadados → distribuição → corpo → conclusões →
assinaturas → rodapé), como se cada seção dependesse da anterior. Elas não dependem:
dado o payload, as quatro primeiras são independentes entre si. A dependência real é
**payload → tudo**. A estrutura de tarefas abaixo reflete isso.

## Goals / Non-Goals

**Goals**

- O documento é **reproduzível**: mesmo escopo + mesmo estado do banco ⇒ mesmo
  conteúdo, exceto o id/data de emissão (que são função do relógio, por definição).
- **Zero derivação no cliente.** Todo número, rótulo, símbolo, autoria e ordenação
  chega pronto no payload. O React é um renderizador burro. Todo teste de correção
  numérica é teste de backend, executável sem DOM.
- **`recorded_at` em 100% das exibições temporais de histórico** (D8).
- Impressão A4 com quebras **previsíveis e testadas**, não emergentes.
- Comportamento no limite de volume **anunciado dentro do próprio documento**.
- Paralelismo real na execução: 4 blocos de renderização independentes atrás de um
  contrato de payload congelado cedo.

**Non-Goals**

- Geração de PDF no servidor (ver Decisão 2 — descartada com custo explicitado).
- Persistência do documento emitido, versionamento de emissões, reemissão histórica.
- Assinatura eletrônica / hash / carimbo de tempo criptográfico.
- Exportação para .docx, .xlsx ou CSV.
- Personalização de layout pelo usuário (logo do cliente, campos extras). Se surgir,
  entra depois — e entra como dado do workspace, não como configuração de CSS.

## Decisions

### D-R1 — O documento é um payload congelado montado inteiramente no servidor

**Decisão.** `GET /api/v1/workspaces/:workspace_id/commissioning_report?scope=...`
retorna um JSON que já é o documento: cabeçalho, carimbo (percentual **e** rótulo),
metadados (id já formatado, escopo já rotulado, contagens da estrutura), distribuição
de status (4 contagens), a árvore com barras de progresso já calculadas por nível,
tarefas com símbolo já escolhido, histórico já ordenado, e a lista de Conclusões já
resolvida. O frontend não faz `reduce`, `sort`, `filter` nem `Math.round` sobre nada
disso.

**Onde a invariante mora.** No `Api::Entities::CommissioningReport` — a entity é o
contrato, e um spec de entity verifica que cada campo derivado está presente. No
frontend, um teste de lint customizado (regra ESLint `no-restricted-syntax`) proíbe
`reduce`/`sort`/`Math.round` dentro de `frontend/src/features/report/`. Não é
elegante; é o que impede a reintrodução silenciosa de cálculo no cliente, que é
exatamente o erro que o legado tinha.

**Alternativa descartada.** Reaproveitar os endpoints de hierarquia já existentes e
montar o documento no cliente. Custo: N+1 de rede proporcional ao nº de robôs, e —
pior — uma segunda implementação da média ponderada em TypeScript, que diverge de
`progress-rollup` no primeiro caso-limite (robô só com `N/A` = 100). Foi rejeitada
por isso, não por performance.

### D-R2 — Impressão é CSS `@page` no navegador, não PDF server-side

**Decisão.** O documento é HTML renderizado pelo React, com uma folha de estilo de
impressão dedicada (`report-print.css`) sob `@media print`, e `@page { size: A4
portrait; margin: 18mm 14mm 20mm 14mm; }`. O usuário imprime com Ctrl+P / "Salvar
como PDF" do próprio sistema.

**Custo assumido.** (a) O resultado depende do motor do navegador — Blink e WebKit
divergem em detalhes de `break-inside`; (b) cabeçalho/rodapé nativos do navegador
(URL, data, "1/12") aparecem por padrão e só o usuário pode desligá-los na caixa de
impressão — mitigamos imprimindo **nosso próprio** rodapé com o id do documento, que
é o que importa juridicamente; (c) não há como gerar o documento sem um humano
apertando imprimir.

**Alternativa descartada: geração server-side (Grover/Puppeteer, wkhtmltopdf ou Prawn).**
Custo real, e é por isso que caiu:
- Chromium headless na imagem Docker: **~400 MB** a mais, mais dependências de fontes
  (Inter precisa estar instalada no container, senão o PDF sai em fallback e o
  `tabular-nums` do §5.1 morre), mais superfície de CVE a atualizar.
- Documento de 200+ páginas não cabe num ciclo de request: vira job Sidekiq + fila
  dedicada + storage do artefato + polling ou notificação de "seu relatório está
  pronto". Isso é uma capacidade inteira, não um detalhe — e recairia sobre
  `delivery-and-observability`, que não a orçou.
- Prawn evitaria o Chromium mas exige **reimplementar todo o layout numa segunda
  linguagem de layout**, sem reuso dos tokens do `design-system`. Duas fontes de
  verdade visual é pior que uma dependência de motor de navegador.

**Reversibilidade.** D-R1 é o que mantém essa porta aberta: como o payload já é o
documento, trocar o renderizador é trocar o consumidor do mesmo JSON. Se o
server-side voltar à mesa, nenhum cálculo precisa se mover.

### D-R3 — Cabeçalho e rodapé repetidos via `<thead>`/`<tfoot>` da tabela raiz

**Decisão.** O corpo inteiro do documento é envolvido, **apenas em `@media print`**,
por uma `<table>` cujo `<thead>` é o cabeçalho e `<tfoot>` é o rodapé. Navegadores
repetem `thead`/`tfoot` em cada página impressa **e reservam o espaço deles no fluxo**.

**Alternativa descartada.** `position: fixed` com `@media print`. Repete visualmente,
mas não reserva espaço no fluxo — o conteúdo passa por baixo do cabeçalho a partir da
segunda página. Descartada por produzir sobreposição, que num documento assinado
significa texto ilegível.

**Alternativa descartada.** `@page { @top-center { content: ... } }` (CSS Paged Media
nível 3). É a resposta correta em teoria e **não é suportada por Blink nem WebKit** —
só por processadores dedicados (PrinceXML, Paged.js). Descartada: adotar Paged.js
seria adicionar um paginador JS de ~100 KB e reescrever o layout no modelo dele.

**Onde mora.** Em `report-print.css` mais uma marcação estrutural fixa em
`ReportDocument.tsx`. Um teste Playwright de impressão (ver Riscos) prova a
repetição, porque CSS de impressão não é testável por unidade.

### D-R4 — A unidade indivisível de quebra é `tarefa + todo o seu histórico`

**Decisão.** Cada tarefa e suas entradas de histórico ficam dentro de um mesmo
`<section class="rpt-task">` com `break-inside: avoid`. Cabeçalhos de projeto, célula
e robô usam `break-after: avoid` (nunca ficam órfãos no pé da página). Blocos de
assinatura têm `break-inside: avoid` e a seção Conclusões usa `break-before: page`.

**Caso-limite reconhecido.** Uma tarefa cujo histórico sozinho ultrapassa uma folha A4
não pode caber, e `break-inside: avoid` degrada para "quebra mesmo assim" (não é uma
falha — é o comportamento definido do CSS). Regra: acima de **18 entradas de
histórico**, a tarefa deixa de ser indivisível e passa a exibir uma faixa
`— histórico continua na próxima página —` na quebra. Isso é decisão de produto: a
alternativa era truncar o histórico da tarefa, e truncar trilha num documento de
aceite é inaceitável.

**Onde mora.** No CSS (`break-inside`, `break-after`) mais uma classe aplicada pelo
componente com base num campo do payload (`history_count`), calculado no servidor.
O limiar 18 é constante nomeada no módulo de configuração do relatório, não número
solto no CSS.

### D-R5 — O carimbo é média simples do progresso **ponderado** dos projetos do escopo

**Decisão.** `stamp.percent = round( Σ project.weighted_progress / nº de projetos )`,
onde `weighted_progress` vem de `progress-rollup` (§2.1: ponderado por peso dentro do
robô, média simples do robô para cima). Escopo `project` ⇒ é o próprio ponderado do
projeto. Escopo sem projeto algum ⇒ `0` / `PENDENTE`.

O rótulo é função só do percentual: `= 100 → CONCLUÍDO`; `> 0 e < 100 → EM ANDAMENTO`;
`= 0 → PENDENTE`. **Não** se olha status de tarefa para decidir o rótulo.

**Alternativa descartada.** Usar a contagem crua (§3.2), que é o número que os hubs
analíticos exibem e portanto o que o usuário acabou de ver na Visão Geral. Descartada
porque a §3.8 é explícita e porque D15 exige que as duas métricas permaneçam
distintas e rotuladas. O risco é de *coerência aparente*: alguém "conserta" o
relatório para bater com o hub. Por isso o teste obrigatório de D15 usa um dataset
onde as duas **divergem** — p.ex. 1 projeto, 1 célula, 1 robô, 2 tarefas: T1 peso 9
a 100% (`Concluído`), T2 peso 1 a 0% (`Pendente`). Ponderado = **90%**; contagem crua
= 1/2 = **50%**. O carimbo tem de dizer 90 e o teste tem de falhar se disser 50.

**Alternativa descartada.** Ponderar a média dos projetos pelo nº de robôs/tarefas de
cada um. Descartada: §2.1 é aritmética simples acima do robô, e o carimbo deve seguir
a mesma lei do resto do sistema.

**Onde mora.** Em `Reports::CommissioningReportService`, lendo `project.progress_cache`
via a API pública de `progress-rollup` — nunca por SQL próprio. Um spec compara o
carimbo com `Progress::WeightedProgress` recalculado do zero, para que uma divergência
de cache apareça como falha aqui também.

### D-R6 — Id do documento: `RT-AAAAMMDD-HHMM`, gerado no servidor, não é chave

**Decisão.** `Reports::DocumentId.for(now)` formata `Time.current.in_time_zone(
workspace.time_zone)` como `"RT-%Y%m%d-%H%M"`. Gerado uma vez por requisição,
congelado no payload, e usado **byte a byte igual** no cabeçalho, nos metadados e no
rodapé — o frontend recebe uma string, não uma data para formatar. `20/07/2026 14:32`
⇒ `RT-20260720-1432`.

**Não é único e não pretende ser.** Duas emissões no mesmo minuto produzem o mesmo id.
É um carimbo temporal de rastreabilidade, coerente com a nota do rodapé.

**Alternativa descartada.** Sequência persistida numa tabela `report_documents` para
garantir unicidade. Custo: uma escrita (e um lock) numa operação de leitura pura,
mais uma tabela e uma política de retenção, para atender um requisito que §3.8 não
faz. Se auditoria de emissões virar requisito, o lugar certo é `audit-log` (§2.8), não
uma tabela nova aqui.

**Alternativa descartada.** Gerar o id no cliente com `new Date()`. Descartada: o
relógio do tablet do chão de fábrica é notoriamente errado, e o id iria para um
documento assinado.

**Fuso.** O fuso é o do workspace, com default `America/Sao_Paulo`. Se
`workspace-tenancy` ainda não expuser `time_zone`, usa-se a constante default e o
campo entra depois — a assinatura de `DocumentId.for` já recebe o fuso como parâmetro
para que isso não vire refatoração.

### D-R7 — Autoria da conclusão: última entrada que chegou a 100, com dois fallbacks

**Decisão.** Para cada tarefa com `progress = 100`:

```sql
SELECT DISTINCT ON (task_id) task_id, author_name_snapshot, recorded_at
FROM task_advances
WHERE task_id = ANY($1) AND to_progress = 100
ORDER BY task_id, recorded_at DESC, created_at DESC
```

1. Havendo entrada: `concluded_by = author_name_snapshot` daquela entrada,
   `concluded_at = recorded_at` daquela entrada.
2. Não havendo (tarefa marcada `Concluído` direto pela máquina de estados §2.2, ou
   dado legado importado sem trilha): `concluded_by` = nomes dos responsáveis atuais
   (`task_assignees`), juntados por `" · "`; `concluded_at` = `nil`, exibido como `—`.
3. Sem entrada **e** sem responsável: `concluded_by` = `—`.

**Por que `author_name_snapshot` e não `join` em `people`.** É a convenção do projeto
(nomes só aparecem como snapshot histórico imutável). Se a pessoa mudar de nome ou
sair da empresa, o documento assinado continua dizendo quem era na hora do ato.

**Por que `recorded_at DESC` e não o primeiro 100.** Uma tarefa pode ir a 100, cair
para 60 e voltar a 100. A conclusão vigente é a última, e a data que interessa ao
aceite é a da conclusão vigente.

**Onde mora.** Em `Reports::CompletionAuthorship`, um objeto próprio, com specs para
os três ramos. O empate exato de `recorded_at` (dois avanços offline no mesmo
segundo) é desempatado por `created_at DESC`, determinístico — não deixamos o
Postgres escolher.

### D-R8 — Orçamento de volume com truncamento **anunciado**, nunca silencioso

**Decisão.** Tetos por documento, constantes nomeadas em `Reports::Budget`:

| Limite | Valor | Ao exceder |
|---|---|---|
| tarefas no escopo | 2.000 | documento renderiza inteiro; **aviso** no topo: escopo grande, considere emitir por projeto |
| entradas de histórico no escopo | 5.000 | histórico é truncado às **10 mais recentes por tarefa**; cada tarefa truncada imprime `(+N entradas anteriores omitidas)`; um aviso em destaque no cabeçalho e no rodapé declara o truncamento e o motivo |
| tarefas no escopo | 8.000 | requisição **recusada** com `422` e mensagem instruindo a emitir por projeto |

O aviso de truncamento é parte do documento impresso, não um toast que some. Um
protocolo de aceite com trilha incompleta e sem dizer que está incompleta é pior que
um erro.

**Alternativa descartada.** Paginação/streaming do payload (buscar o documento em
lotes). Descartada: quebra a atomicidade — lotes lidos em momentos diferentes podem
refletir estados diferentes do banco, e o documento deixa de ser um retrato de um
instante. Um documento de aceite montado de retratos inconsistentes é exatamente o
defeito que estamos tentando evitar.

**Alternativa descartada.** Deixar sem teto e confiar no navegador. Descartada: o modo
de falha é a aba travando durante a impressão, com o cliente na sala.

**Orçamento de query.** O payload é montado em **≤ 5 queries constantes**,
independentes do nº de projetos: (1) árvore projeto/célula/robô com `progress_cache`;
(2) tarefas + responsáveis agregados; (3) avanços por `task_id = ANY(...)` com
`LIMIT` por partição via window function; (4) contagens de status agregadas; (5)
autoria das conclusões. Um teste de contagem de queries falha o CI em caso de N+1.

### D-R9 — Todo texto fixo é format string versionada (D14)

**Decisão.** `config/locales/pt-BR.report.yml`, namespace `report.v1.*`: título,
rótulos de carimbo, nomes das seções, cabeçalhos de coluna, rótulos de status,
`de→para`, rótulos de assinatura, nota de rastreabilidade, avisos de truncamento.
Versionado (`v1`) porque mudar o texto de um documento assinado é mudança material —
a chave nova convive com a antiga em vez de sobrescrevê-la.

**Onde mora.** O **servidor** entrega os textos já resolvidos dentro do payload. O
frontend não tem cópia dessas strings; só rótulos de UI do redor (botão "Imprimir",
seletor de escopo) ficam no módulo de strings do frontend. Um sweep de teste
(`spec/i18n/report_literals_spec.rb` + regra ESLint) falha se aparecer literal em
português dentro de `features/report/`.

**Alternativa descartada.** Textos no frontend, servidor devolvendo só dados.
Descartada porque então existiriam duas cópias das strings do documento (a do PDF
hipotético de D-R2 e a do React) e elas divergiriam.

### D-R10 — Os 4 glifos são um conjunto fechado, num módulo único

`✓` Concluído · `◐` Em andamento · `○` Pendente · `—` N/A. §5.1 proíbe emoji em toda
a UI e declara estes como a **única** exceção. Eles vivem num mapa único
(`STATUS_GLYPH`) no backend, viajam no payload, e um teste falha se qualquer
caractere fora da faixa ASCII + `{✓ ◐ ○ —}` aparecer no payload de textos fixos.
São caracteres tipográficos, não ícones: herdam o peso da Inter e não dependem de
fonte de emoji instalada no container ou no tablet.

### D-R11 — Estrutura de execução paralela em vez de cadeia linear

Dado o payload, **cabeçalho+carimbo, metadados+id, distribuição de status e corpo
hierárquico não dependem um do outro**. O grafo real é:

```
[1 contrato de payload + entity]  →  [2 header/stamp] ┐
                                  →  [3 metadados/id] ├→ [6 print layout] → [7 verificação]
                                  →  [4 distribuição] │
                                  →  [5 corpo+histórico] ┘ → [5b conclusões]
```

Só `conclusões` depende do corpo (reusa o mesmo resolvedor de tarefa) e só o layout
de impressão depende de existir marcação. Os grupos 2–5 são paralelizáveis entre
pessoas. Por isso o `tasks.md` congela a entity **primeiro** e com fixture de payload
publicada: é o contrato que permite trabalhar em paralelo sem integração dolorosa.

## Risks / Trade-offs

- **Divergência entre carimbo e hubs.** Usuário vê 50% no hub e 90% no carimbo e abre
  chamado de bug. Mitigação: rotulagem explícita exigida por D15 — o relatório diz
  "progresso ponderado" ao lado do número. Aceito conscientemente; não unificar.
- **`progress_cache` desatualizado.** O carimbo herda qualquer erro do cache de D5.
  Mitigação: o job de reconciliação de `progress-rollup` é pré-requisito operacional;
  nosso spec compara carimbo com recálculo do zero e falha na divergência. **Não**
  recalculamos on-the-fly no relatório — isso mascararia o bug em vez de expô-lo.
- **CSS de impressão não é testável por unidade.** Mitigação: um Playwright em
  `quality-and-accessibility` gera PDF via CDP (`Page.printToPDF`) sobre um dataset
  fixo e afirma nº de páginas, presença do cabeçalho em cada página e ausência de
  quebra dentro de `.rpt-task`. Roda no CI. Sem isso, D-R3 e D-R4 são texto.
- **Divergência entre motores.** Firefox trata `break-inside: avoid` em `<section>` de
  forma diferente de Blink. Mitigação: navegadores-alvo declarados (Chrome/Edge,
  Safari); Firefox é suportado, não garantido pixel a pixel. Documentado ao usuário.
- **`recorded_at` no futuro ou absurdo.** Vem do cliente (D8) — relógio errado do
  tablet coloca um avanço em 2031 e ele aparece assim no documento assinado. **A
  sanidade de `recorded_at` é responsabilidade de `progress-advances`, não nossa**;
  aqui apenas não reordenamos nem "corrigimos" nada. Ordenar por `recorded_at`
  significa que um relógio errado bagunça a ordem visual — trade-off aceito, porque a
  alternativa (ordenar por `created_at` e exibir `recorded_at`) produziria uma lista
  cujos horários parecem fora de ordem, que é pior num documento assinado.
- **Truncamento de histórico em escopo grande.** Um workspace grande pode gerar um
  documento com trilha parcial. Mitigado por ser anunciado e por o caminho recomendado
  (`scope=project`) quase nunca estourar. Risco residual: alguém assinar sem ler o
  aviso.
- **Sem persistência de emissões.** Não há como provar depois qual documento foi
  assinado. Aceito: o documento em papel é a prova, e a trilha `task_advances` é
  imutável. Se virar requisito, ver Perguntas em aberto.
- **Custo de reverter D-R2.** Se o cliente exigir PDF gerado pelo servidor, entram
  Chromium na imagem, job assíncrono, storage e notificação — semanas, não dias, e
  atinge `delivery-and-observability`. D-R1 limita o dano ao renderizador.

## Plano de migração

Não há migração de dados: capacidade somente-leitura, sem tabela nova.

Ordem operacional:
1. `progress-rollup` precisa estar entregue **com o job de reconciliação rodando** —
   sem ele o carimbo pode carimbar um cache podre num documento assinado.
2. `progress-advances` precisa ter `recorded_at` populado e o índice
   `task_advances(task_id, recorded_at DESC)` criado. Registros importados por
   `legacy-data-migration` sem `recorded_at` devem ter recebido *backfill* a partir
   de `ts` do legado; se algum ficar nulo, o relatório o exibe como `—` e **não** cai
   para `created_at` (isso violaria D8 justamente no caso em que a diferença importa).
3. Rollback: remover a rota e o item de menu. Nada a desfazer no banco.

## Perguntas em aberto

1. **Fuso do workspace.** `workspace-tenancy` vai expor `workspaces.time_zone`? Até lá,
   default `America/Sao_Paulo`. Afeta o id do documento perto da meia-noite.
2. **Escopo por célula ou por robô.** §3.8 pede só "todos" ou "um projeto". Vale expor
   `scope=cell` / `scope=robot` na v1? Proposta: **não** — o payload já suporta, mas o
   seletor fica com dois modos até haver pedido real.
3. **Emissão registrada em auditoria.** Gerar o relatório deveria virar linha em
   `audit_logs` (§2.8)? Argumento a favor: rastreabilidade de quem emitiu o que o
   cliente assinou. Contra: §2.8 lista apenas conclusão de tarefa como evento
   automático, e o log é limitado a 200 registros na exibição. **Decisão pendente com
   `audit-log`** — não implementar unilateralmente.
4. **Logo/identidade do cliente no cabeçalho.** Pedido provável no primeiro uso real.
   Se aceito, é dado de workspace (`workspace-settings`), não CSS.
5. **Membro `view` pode emitir?** Assumido **sim** (é leitura pura, e o leitor
   frequentemente é quem confere com o cliente). Confirmar contra a matriz §4.1 com
   `authorization-policies`.
