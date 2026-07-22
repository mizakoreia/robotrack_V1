# Tarefas — commissioning-report

> **Ordem de execução.** O grupo 1 congela o contrato do payload e é bloqueante.
> Depois disso, os grupos **2, 3, 4 e 5 são independentes entre si** e podem ser
> executados em paralelo (o plano anterior os encadeava linearmente sem motivo — dado
> o payload, cabeçalho, metadados, distribuição e corpo não se conhecem). O grupo 6
> depende de 5 (reusa o resolvedor de tarefa). O grupo 7 depende de existir marcação
> (2–6). O grupo 8 fecha.

## 1. Contrato do payload e endpoint (bloqueante)

- [x] 1.1 Definir `Api::Entities::CommissioningReport` com todos os campos derivados (carimbo, id, contagens, árvore, histórico, conclusões, avisos de volume) e publicar uma fixture JSON congelada em `spec/fixtures/reports/commissioning_report.json`, consumida por backend e frontend. (§3.8 — a fixture é o contrato; se um campo derivado faltar, o consumidor teria de calcular, e os grupos paralelos destravariam com o formato errado)
- [x] 1.2 Implementar `Reports::CommissioningReportService` no contrato singleton `ApiResponseHandler`, com resolução de escopo `all` / `project` e recusa `400` para qualquer outro valor. (§3.8 — `scope=cell` responde `400`, não silenciosamente `all`)
- [x] 1.3 Montar o endpoint `GET /api/v1/workspaces/:workspace_id/commissioning_report` em `api/v1/base.rb` com policy explícita (D3): membro `view`/`edit`/dono emitem; não-membro recebe `404` sem vazar nome nem contagens. (§4.1 inv. 1 — um `GET` com token de outro tenant não pode devolver `403` com o nome do workspace na mensagem)
- [x] 1.4 Implementar a montagem em ≤5 queries constantes, com `task_advances` buscado por `task_id = ANY(...)`. (§3.8 — teste de contagem de queries sobre 8 projetos/200 robôs falha se o número crescer com o nº de projetos)
- [x] 1.5 **Verificação:** spec de request cobrindo os 4 caminhos de autorização (view → `200`, não-membro → `404`, projeto de outro workspace → `404`, `X-Skip-Auth: 1` → `401`), com o teste de RLS removendo a checagem de aplicação. (§4.1 inv. 1/2 — o `404` cross-tenant tem de vir do banco, não do Ruby)

## 2. Cabeçalho e carimbo

- [x] 2.1 Implementar o cálculo do carimbo como média aritmética simples do `weighted_progress` dos projetos do escopo, lido da API pública de `progress-rollup` — sem SQL próprio de progresso. (§2.1/D15 — dataset T1 peso 9 a 100% + T2 peso 1 a 0% carimba `90%`, não `50%`)
- [x] 2.2 Implementar o rótulo (`CONCLUÍDO` = 100 / `EM ANDAMENTO` > 0 / `PENDENTE` = 0) a partir apenas do percentual, com chaves `report.v1.stamp_label_*`. (§3.8 — escopo com todas as tarefas em `N/A` chega a 100 ponderado e carimba `CONCLUÍDO` sem consultar status)
- [x] 2.3 Renderizar o cabeçalho (título, nome do workspace, carimbo) consumindo apenas campos do payload. (§3.8 — a regra ESLint proíbe `reduce`/`Math.round` em `features/report/`; o componente falha o lint se recalcular)
- [x] 2.4 **Verificação:** spec comparando o carimbo contra o recálculo ponderado do zero (ignorando `progress_cache`) em 4 datasets: 100%, 0%, projetos de tamanhos díspares (100 e 0 → 50) e escopo vazio (0/`PENDENTE`). (§2.1 — cache podre aparece como falha aqui, não como número errado num documento assinado)

## 3. Metadados e id do documento

- [x] 3.1 Implementar `Reports::DocumentId.for(instant, time_zone)` formatando `RT-%Y%m%d-%H%M`, gerado uma única vez por requisição e congelado no payload. (§3.8 — 20/07/2026 14:32 → `RT-20260720-1432`; 05/03/2026 09:07 → `RT-20260305-0907`, com zero-padding)
- [x] 3.2 Montar o bloco de metadados (escopo rotulado, id, emitido em, gerado por, estrutura `N projeto(s) · N célula(s) · N robô(s) · N tarefa(s)`), contando apenas o escopo emitido. (§3.8 — `scope=project` sobre projeto com 3 células conta `1 projeto(s)`, não os 2 do workspace)
- [x] 3.3 **Verificação:** spec de id com relógio congelado em 3 instantes (incluindo 23:59 num fuso diferente do UTC) provando que o id dos metadados e o do rodapé são byte a byte iguais. (§3.8 — id gerado duas vezes na mesma requisição pode cruzar o minuto e produzir documento com dois ids)

## 4. Distribuição de status e glifos

- [x] 4.1 Definir o mapa único `STATUS_GLYPH` (`✓ ◐ ○ —`) no servidor e as contagens agregadas por status do escopo, com as 4 linhas sempre presentes inclusive zeradas. (§3.8/§5.1 — escopo sem nenhuma tarefa `N/A` exibe `— N/A 0`, não omite a linha)
- [x] 4.2 Renderizar a distribuição no documento consumindo os glifos do payload, sem repetir caractere em JSX. (§5.1 — glifo duplicado no componente é o vetor pelo qual um emoji entra depois)
- [x] 4.3 **Verificação:** spec afirmando que a soma das 4 contagens é igual ao total de tarefas dos metadados, em dataset 12/9/15/4 = 40. (§3.8 — tarefa contada em dois status, ou status desconhecido caindo fora das 4 linhas, faz a soma divergir do total)

## 5. Corpo hierárquico e histórico por tarefa

- [ ] 5.1 Montar a árvore projeto → célula → robô no payload com progresso ponderado por nível, Aplicação do robô e ordenação manual (§2.9), tolerante a níveis vazios. (§2.9/§1.4 — projeto sem células renderiza com barra `0%`, não estoura `NoMethodError`)
- [ ] 5.2 Montar a tabela de tarefas (símbolo, descrição, status, %, responsáveis) com responsáveis vindos de `task_assignees` por id. (D11 — tarefa sem responsável exibe `—`; a string `Não Atribuído` não pode aparecer no documento)
- [ ] 5.3 Anexar o histórico por tarefa ordenado por `recorded_at` crescente (desempate `created_at`), expondo `recorded_at` como campo de data e tratando nulo como `—`, sem fallback para `created_at`. (D8 — avanço com `recorded_at 14:02` e `created_at 17:41` aparece como 14:02, e `17:41` não existe no payload)
- [ ] 5.4 Renderizar o corpo em React, sem bloco de histórico para tarefas sem entradas. (§3.8 — tarefa `Pendente` sem avanço não pode imprimir cabeçalho de histórico vazio ocupando folha)
- [ ] 5.5 **Verificação:** spec de payload sobre um dataset com projeto vazio, célula vazia, tarefa sem responsável, tarefa sem histórico e entrada com `recorded_at` nulo — todos no mesmo documento. (§1.4/§3.8 — qualquer um deles isoladamente quebra o render; o teste precisa dos cinco juntos)

## 6. Seção Conclusões (depende de 5)

- [ ] 6.1 Implementar `Reports::CompletionAuthorship` com `DISTINCT ON (task_id)` sobre `to_progress = 100`, ordenado por `recorded_at DESC, created_at DESC`. (D-R7 — tarefa que foi a 100, caiu a 60 e voltou a 100 atribui à última entrada, não à primeira)
- [ ] 6.2 Implementar os dois fallbacks: responsáveis atuais quando não há entrada de 100; `—` quando também não há responsáveis. (§3.8 — tarefa em `Concluído` marcada direto pela máquina de estados §2.2 não pode sumir das Conclusões)
- [ ] 6.3 Renderizar a seção Conclusões com quem concluiu e quando, incluindo apenas tarefas com progresso 100. (§3.8 — tarefa a 95% ou em `N/A` não pode aparecer na lista)
- [ ] 6.4 **Verificação:** spec dos três ramos de autoria no mesmo documento, incluindo o caso em que o autor da entrada de 100% difere do responsável atual. (D-R7 — atribuir ao responsável atual é o erro que passa em qualquer teste que não troque o responsável depois da conclusão)

## 7. Assinaturas, rodapé e layout de impressão A4

- [ ] 7.1 Renderizar os blocos `Comissionador` e `Cliente / Aceite` com áreas em branco, e o rodapé com id, data de geração e nota de rastreabilidade da chave de locale. (§3.8 — nenhum bloco vem pré-preenchido com o usuário logado, e o id do rodapé é o carimbado, não um segundo `Time.current`)
- [ ] 7.2 Escrever `report-print.css` com `@page A4 portrait`, margens `18mm 14mm 20mm 14mm` e neutralização do tema escuro na impressão. (§5.1 — imprimir com tema escuro ativo não pode sair com fundo preto nem barras indistinguíveis em monocromático)
- [ ] 7.3 Implementar a tabela raiz de impressão com `<thead>`/`<tfoot>` para repetir cabeçalho e rodapé, apenas sob `@media print`. (D-R3 — `position: fixed` repete mas não reserva espaço; a partir da página 2 o corpo passaria por baixo do cabeçalho)
- [ ] 7.4 Aplicar as regras de quebra (`.rpt-task` indivisível, cabeçalhos de nível com `break-after: avoid`, assinaturas indivisíveis, Conclusões em nova página) e a faixa `— histórico continua na próxima página —` acima de 18 entradas, com o limiar como constante nomeada. (D-R4 — tarefa com 6 entradas iniciando a 3 linhas do fim vai inteira para a página seguinte; a de 24 entradas não cabe e precisa da faixa)
- [ ] 7.5 **Verificação:** teste Playwright que gera PDF via `Page.printToPDF` sobre dataset fixo e afirma nº de páginas, cabeçalho e rodapé em **todas** as páginas, e ausência de quebra dentro de `.rpt-task`. (D-R3/D-R4 — CSS de impressão não é testável por unidade; sem este teste as duas decisões são só texto)

## 8. Volume, i18n, tela e fechamento

- [ ] 8.1 Implementar `Reports::Budget` com os três tetos (2.000 tarefas → aviso; 5.000 entradas → truncar às 10 mais recentes por tarefa; 8.000 tarefas → `422`) e renderizar os avisos **dentro do documento impresso**, incluindo `(+N entradas anteriores omitidas)` por tarefa truncada. (D-R8 — 8.400 tarefas responde `422` antes de montar o payload; truncamento anunciado só por toast some antes da assinatura)
- [ ] 8.2 Criar `config/locales/pt-BR.report.yml` sob `report.v1.*` com todos os textos fixos resolvidos no servidor, e adicionar o sweep de literais (spec de i18n + regra ESLint em `features/report/`) e o sweep de glifos fora de `{✓ ◐ ○ —}`. (D14/§5.1 — chave ausente falha o spec; o documento nunca sai com `translation missing`, e emoji introduzido depois não passa despercebido)
- [ ] 8.3 Implementar a tela do relatório: rota, seletor de escopo, query key `['ws', wsId, 'report', scope]`, estados de carregamento, erro e offline. (§4.3 — sem conexão informa e oferece retry; nunca monta o documento a partir de cache parcial)
- [ ] 8.4 **Verificação:** teste de integração ponta a ponta emitindo o relatório de um dataset de carga (2.300 tarefas / 3.100 entradas) afirmando: aviso de escopo grande presente, truncamento ausente, ≤5 queries e tempo de resposta dentro do orçamento. (D-R8 — a fronteira 2.300/3.100 é o único caso que distingue "avisa" de "trunca")
