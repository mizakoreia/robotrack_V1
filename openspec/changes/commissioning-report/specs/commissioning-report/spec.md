## ADDED Requirements

### Requirement: Escopo do relatório

O sistema SHALL oferecer exatamente dois escopos de emissão do Protocolo de
Comissionamento: `all` (todos os projetos do workspace corrente) e `project` (um
projeto identificado por `project_id`). O escopo SHALL ser refletido textualmente
nos metadados do documento. Qualquer outro valor de `scope` SHALL ser recusado com
`400`.

#### Scenario: Escopo `all` inclui todos os projetos do workspace

- **WHEN** o workspace tem 3 projetos ("Linha A", "Linha B", "Linha C") e o relatório é emitido com `scope=all`
- **THEN** o corpo hierárquico SHALL conter os 3 projetos, nessa ordem de `position`
- **AND** os metadados SHALL declarar o escopo como "Todos os projetos"

#### Scenario: Escopo `project` inclui apenas o projeto pedido

- **WHEN** o relatório é emitido com `scope=project&project_id=<id de "Linha B">`
- **THEN** o corpo hierárquico SHALL conter somente "Linha B"
- **AND** os metadados SHALL declarar o escopo como "Projeto: Linha B"

#### Scenario: Valor de escopo inválido é recusado

- **WHEN** o relatório é requisitado com `scope=cell`
- **THEN** o sistema SHALL responder `400` e NÃO SHALL montar documento algum

### Requirement: Carimbo com percentual ponderado e rótulo

O sistema SHALL calcular o percentual do carimbo como a **média aritmética simples
dos progressos ponderados (§2.1) dos projetos do escopo**, arredondada para inteiro,
lida de `progress-rollup`. O rótulo SHALL ser `CONCLUÍDO` quando o percentual for
exatamente 100, `EM ANDAMENTO` quando maior que 0 e menor que 100, e `PENDENTE`
quando for 0. O sistema NÃO SHALL usar a contagem crua (§3.2) em nenhum ponto do
documento.

#### Scenario: Escopo com um projeto a 100% carimba CONCLUÍDO

- **WHEN** o escopo contém um único projeto cujo progresso ponderado é 100
- **THEN** o carimbo SHALL exibir `100%` e o rótulo `CONCLUÍDO`

#### Scenario: Escopo com um projeto a 0% carimba PENDENTE

- **WHEN** o escopo contém um único projeto cujo progresso ponderado é 0
- **THEN** o carimbo SHALL exibir `0%` e o rótulo `PENDENTE`

#### Scenario: Média entre projetos é simples, não ponderada por tamanho

- **WHEN** o escopo `all` contém o projeto "Linha A" (1 célula, 1 robô, ponderado 100) e o projeto "Linha B" (4 células, 20 robôs, ponderado 0)
- **THEN** o carimbo SHALL exibir `50%` e o rótulo `EM ANDAMENTO`
- **AND** NÃO SHALL exibir um valor ponderado pelo número de robôs (que seria `5%`)

#### Scenario: Dataset onde ponderado e contagem crua divergem carimba o ponderado (D15)

- **WHEN** o escopo tem 1 projeto → 1 célula → 1 robô com 2 tarefas: T1 peso 9 em `Concluído`/100% e T2 peso 1 em `Pendente`/0%
- **THEN** o progresso ponderado do projeto SHALL ser `90` e o carimbo SHALL exibir `90%` com rótulo `EM ANDAMENTO`
- **AND** o carimbo NÃO SHALL exibir `50%` (a contagem crua de 1 concluída ÷ 2 tarefas)

#### Scenario: Escopo sem projeto algum

- **WHEN** o workspace não tem nenhum projeto e o relatório é emitido com `scope=all`
- **THEN** o carimbo SHALL exibir `0%` com rótulo `PENDENTE`
- **AND** a estrutura SHALL declarar `0 projeto(s) · 0 célula(s) · 0 robô(s) · 0 tarefa(s)`

### Requirement: Cabeçalho do documento

O sistema SHALL exibir no topo do documento o título fixo `PROTOCOLO DE
COMISSIONAMENTO`, o nome do workspace corrente e o carimbo. O título SHALL vir da
chave de locale `report.v1.title` e NÃO SHALL ser literal no código de apresentação.

#### Scenario: Cabeçalho traz título, workspace e carimbo

- **WHEN** o relatório do workspace "Comissionamento Pintura 3" é emitido com carimbo 62%
- **THEN** o cabeçalho SHALL conter `PROTOCOLO DE COMISSIONAMENTO`, `Comissionamento Pintura 3` e o carimbo `62% · EM ANDAMENTO`

### Requirement: Id do documento no formato RT-AAAAMMDD-HHMM

O sistema SHALL gerar o id do documento no servidor, no formato
`RT-AAAAMMDD-HHMM`, a partir do instante da emissão convertido para o fuso do
workspace (padrão `America/Sao_Paulo`). O id SHALL ser gerado uma única vez por
emissão e SHALL aparecer idêntico nos metadados e no rodapé. O cliente NÃO SHALL
gerar nem reformatar o id.

#### Scenario: Id gerado às 14h32 de 20/07/2026

- **WHEN** o relatório é emitido em 20/07/2026 às 14:32 no fuso do workspace
- **THEN** o id do documento SHALL ser exatamente `RT-20260720-1432`

#### Scenario: Zero-padding de mês, dia e hora

- **WHEN** o relatório é emitido em 05/03/2026 às 09:07 no fuso do workspace
- **THEN** o id do documento SHALL ser exatamente `RT-20260305-0907`

#### Scenario: Id é o mesmo nos metadados e no rodapé

- **WHEN** um documento é emitido
- **THEN** a string de id nos metadados SHALL ser byte a byte igual à do rodapé

### Requirement: Metadados do documento

O sistema SHALL exibir um bloco de metadados com: escopo, id do documento, data e
hora de emissão, nome de quem gerou, e a estrutura no formato
`N projeto(s) · N célula(s) · N robô(s) · N tarefa(s)`. As contagens SHALL refletir
apenas o escopo emitido.

#### Scenario: Estrutura conta apenas o escopo emitido

- **WHEN** o workspace tem 2 projetos, mas o relatório é emitido com `scope=project` sobre um projeto de 3 células, 7 robôs e 210 tarefas
- **THEN** a estrutura SHALL exibir `1 projeto(s) · 3 célula(s) · 7 robô(s) · 210 tarefa(s)`

#### Scenario: Gerado por traz o nome de exibição do autor

- **WHEN** a pessoa "Marina Alves" emite o relatório
- **THEN** o campo "gerado por" SHALL exibir `Marina Alves`

### Requirement: Distribuição de status com glifos tipográficos

O sistema SHALL exibir a contagem de tarefas do escopo por status, cada uma
acompanhada de seu glifo: `✓` Concluído, `◐` Em andamento, `○` Pendente, `—` N/A.
A soma das quatro contagens SHALL ser igual ao total de tarefas declarado nos
metadados. Nenhum outro glifo ou emoji SHALL aparecer no documento.

#### Scenario: Contagens somam o total da estrutura

- **WHEN** o escopo tem 40 tarefas: 12 `Concluído`, 9 `Em Andamento`, 15 `Pendente`, 4 `N/A`
- **THEN** a distribuição SHALL exibir `✓ Concluído 12`, `◐ Em andamento 9`, `○ Pendente 15`, `— N/A 4`
- **AND** a soma `12 + 9 + 15 + 4` SHALL ser igual ao `40 tarefa(s)` dos metadados

#### Scenario: Status sem nenhuma tarefa aparece com zero

- **WHEN** o escopo não tem nenhuma tarefa em `N/A`
- **THEN** a distribuição SHALL exibir `— N/A 0` e NÃO SHALL omitir a linha

### Requirement: Corpo hierárquico projeto → célula → robô → tarefa

O sistema SHALL renderizar o corpo do documento na hierarquia projeto → célula →
robô, cada nível com seu nome e sua barra de progresso **ponderado** (§2.1)
explicitamente rotulada. O robô SHALL exibir também sua Aplicação (§1.2). Cada robô
SHALL trazer uma tabela de tarefas com as colunas: símbolo de status, descrição,
status, percentual e responsáveis. A ordem SHALL seguir a ordenação manual (§2.9) de
projetos, células e robôs.

#### Scenario: Robô exibe Aplicação e barra de progresso ponderado

- **WHEN** o robô "R03 - Sealing" tem Aplicação `Sealing` e progresso ponderado 45
- **THEN** o documento SHALL exibir `R03 - Sealing`, `Sealing` e uma barra rotulada como progresso ponderado em `45%`

#### Scenario: Tarefa sem responsável não exibe sentinela

- **WHEN** uma tarefa não tem nenhum responsável (D11)
- **THEN** a coluna de responsáveis SHALL exibir `—`
- **AND** NÃO SHALL exibir a string `Não Atribuído`

#### Scenario: Leitura tolerante de nível vazio

- **WHEN** um projeto do escopo não tem nenhuma célula, e uma célula de outro projeto não tem nenhum robô
- **THEN** o documento SHALL renderizar o projeto e a célula com barra em `0%` e uma linha de conteúdo vazio
- **AND** NÃO SHALL falhar nem omitir o nível

### Requirement: Histórico exibido abaixo de cada tarefa usando recorded_at

O sistema SHALL exibir, imediatamente abaixo de cada tarefa, todas as suas entradas
de histórico com: data e hora, autor, transição `de→para` e comentário. A data e
hora exibida SHALL ser `recorded_at` (quando a pessoa agiu), NUNCA `created_at`
(quando o servidor persistiu), conforme D8. As entradas SHALL ser ordenadas por
`recorded_at` crescente, desempatadas por `created_at` crescente.

#### Scenario: Avanço registrado às 14h e sincronizado às 17h consta como 14h

- **WHEN** uma entrada de histórico tem `recorded_at = 2026-07-20 14:02` e `created_at = 2026-07-20 17:41`
- **THEN** o documento SHALL exibir `20/07/2026 14:02` para essa entrada
- **AND** NÃO SHALL exibir `17:41` em nenhum lugar dessa entrada

#### Scenario: Entrada exibe autor, transição e comentário

- **WHEN** uma entrada tem autor "João Pedro", `from_progress = 45`, `to_progress = 70` e comentário "Trajetória com peça validada"
- **THEN** o documento SHALL exibir `João Pedro`, `45% → 70%` e `Trajetória com peça validada`

#### Scenario: Entrada sem recorded_at não cai para created_at

- **WHEN** uma entrada importada do legado tem `recorded_at` nulo e `created_at = 2026-01-10 08:00`
- **THEN** o documento SHALL exibir `—` no campo de data dessa entrada
- **AND** NÃO SHALL exibir `10/01/2026 08:00`

#### Scenario: Tarefa sem histórico não exibe bloco vazio

- **WHEN** uma tarefa em `Pendente` nunca recebeu avanço
- **THEN** o documento SHALL exibir a linha da tarefa sem nenhuma entrada de histórico abaixo dela
- **AND** NÃO SHALL exibir cabeçalho de histórico vazio

### Requirement: Seção Conclusões com autoria resolvida

O sistema SHALL incluir uma seção "Conclusões" listando **todas** as tarefas do
escopo com progresso 100, indicando quem concluiu e quando. Quem concluiu SHALL ser
o `author_name_snapshot` da entrada de histórico mais recente por `recorded_at` cujo
`to_progress` seja 100. Não havendo tal entrada, o sistema SHALL usar como fallback
os responsáveis atuais da tarefa. Não havendo responsáveis, SHALL exibir `—`.

#### Scenario: Autor da entrada de 100% prevalece sobre o responsável atual

- **WHEN** a tarefa "TCP Check" foi levada a 100% por "Carlos Nunes" e depois teve seus responsáveis alterados para "Marina Alves"
- **THEN** as Conclusões SHALL atribuir a conclusão a `Carlos Nunes`
- **AND** NÃO SHALL atribuí-la a `Marina Alves`

#### Scenario: Tarefa a 100% sem histórico cai no fallback dos responsáveis

- **WHEN** a tarefa "Payload" está em `Concluído`/100% sem nenhuma entrada de histórico e tem os responsáveis "Ana Lima" e "Rui Sá"
- **THEN** as Conclusões SHALL exibir `Ana Lima · Rui Sá` como quem concluiu
- **AND** SHALL exibir `—` no campo de quando

#### Scenario: Tarefa a 100% sem histórico e sem responsável

- **WHEN** a tarefa "Speed up" está em `Concluído`/100%, sem histórico e sem responsáveis
- **THEN** as Conclusões SHALL exibir `—` em quem concluiu e `—` em quando

#### Scenario: Reconclusão usa a entrada mais recente

- **WHEN** a tarefa foi a 100% por "Ana Lima" em 01/06/2026, caiu para 60% e voltou a 100% por "Rui Sá" em 15/06/2026
- **THEN** as Conclusões SHALL exibir `Rui Sá` e `15/06/2026`

#### Scenario: Tarefa em N/A não entra nas Conclusões

- **WHEN** uma tarefa está em `N/A` com progresso 0 e outra está em `Em Andamento` com 95%
- **THEN** nenhuma das duas SHALL aparecer na seção Conclusões

### Requirement: Blocos de assinatura e rodapé

O sistema SHALL incluir, ao final do documento, dois blocos de assinatura rotulados
`Comissionador` e `Cliente / Aceite`, cada um com linha para nome, assinatura e data.
O rodapé SHALL conter o id do documento, a data de geração e a nota de
rastreabilidade.

#### Scenario: Ambos os blocos de assinatura presentes e vazios

- **WHEN** o documento é emitido
- **THEN** SHALL existir exatamente um bloco `Comissionador` e um bloco `Cliente / Aceite`
- **AND** ambos SHALL ter área em branco para assinatura manuscrita, sem preenchimento automático

#### Scenario: Rodapé traz id, data e nota de rastreabilidade

- **WHEN** o documento `RT-20260720-1432` é emitido
- **THEN** o rodapé SHALL conter `RT-20260720-1432`, a data de geração e a nota de rastreabilidade da chave `report.v1.footer_traceability`

### Requirement: Textos fixos do documento em format strings versionadas

Todo texto fixo do documento SHALL vir de `config/locales/pt-BR.report.yml` sob o
namespace `report.v1.*` e SHALL ser resolvido no servidor, viajando já formatado no
payload. Nenhum literal em português SHALL existir no código de apresentação do
relatório.

#### Scenario: Sweep de literais falha o build

- **WHEN** um literal em português é introduzido em `frontend/src/features/report/`
- **THEN** o sweep de i18n SHALL falhar o CI apontando o arquivo e a linha

#### Scenario: Chave de locale ausente falha o teste, não o documento

- **WHEN** a chave `report.v1.stamp_label_done` está ausente do arquivo de locale
- **THEN** o spec de completude de locale SHALL falhar
- **AND** o serviço NÃO SHALL emitir um documento contendo `translation missing`

### Requirement: Payload congelado sem derivação no cliente

O servidor SHALL entregar o documento como um único payload contendo todos os
valores já derivados: percentual e rótulo do carimbo, id do documento, contagens de
estrutura e de status, progresso de cada nível, símbolo de cada tarefa, histórico
ordenado e Conclusões resolvidas. O cliente NÃO SHALL calcular médias, somas,
ordenações ou escolhas de autoria.

#### Scenario: Cliente renderiza sem recalcular

- **WHEN** o payload declara carimbo `73%` e a soma dos progressos dos projetos, se recalculada no cliente, daria `74%` por arredondamento diferente
- **THEN** o documento SHALL exibir `73%`

#### Scenario: Payload é montado em número constante de queries

- **WHEN** o relatório é emitido sobre um escopo de 8 projetos, 40 células e 200 robôs
- **THEN** o serviço SHALL executar no máximo 5 queries
- **AND** o teste de contagem de queries SHALL falhar o CI se o número crescer com o nº de projetos

### Requirement: Autorização e isolamento de tenant na emissão

A emissão do relatório SHALL exigir associação ativa ao workspace corrente. Membros
com papel `view` SHALL poder emitir (é leitura pura). O endpoint SHALL declarar sua
policy explicitamente (D3) e o isolamento SHALL ser garantido por RLS (D2), não
apenas por escopo no model.

#### Scenario: Membro somente-leitura emite o relatório

- **WHEN** um membro com papel `view` requisita o relatório do workspace ao qual pertence
- **THEN** o sistema SHALL responder `200` com o documento completo

#### Scenario: Usuário sem associação não emite

- **WHEN** um usuário autenticado sem associação ao workspace `W1` requisita o relatório de `W1`
- **THEN** o sistema SHALL responder `404` e NÃO SHALL revelar a existência, o nome ou as contagens de `W1`

#### Scenario: Escopo apontando para projeto de outro workspace

- **WHEN** um membro de `W1` requisita `scope=project&project_id=<projeto de W2>`
- **THEN** o sistema SHALL responder `404`
- **AND** o RLS SHALL impedir a leitura da linha mesmo se a checagem de aplicação for removida

#### Scenario: Requisição sem autenticação

- **WHEN** o endpoint é chamado sem token, ou com o header `X-Skip-Auth: 1`
- **THEN** o sistema SHALL responder `401`
