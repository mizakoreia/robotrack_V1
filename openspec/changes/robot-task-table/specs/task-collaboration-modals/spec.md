# task-collaboration-modals

## ADDED Requirements

### Requirement: Modal de histórico da tarefa

O sistema SHALL exibir, no modal de histórico, a lista de contribuidores da tarefa e
uma timeline ordenada do mais recente para o mais antigo, com autor, `de% → para%`,
data/hora e comentário de cada entrada (§3.5).

#### Scenario: Timeline ordena do mais recente para o mais antigo

- **WHEN** a tarefa tem avanços com `recorded_at` `10:00 (0→20)`, `11:30 (20→60)` e
  `09:00 (—)` de ontem
- **THEN** a primeira entrada exibida SHALL ser a de `11:30` e a última SHALL ser a
  de ontem às `09:00`

#### Scenario: Cada entrada exibe autor, transição e comentário

- **WHEN** existe um avanço de `Ana` de 20 para 60 com o comentário
  `Solda dos pontos 1 a 8`
- **THEN** a entrada SHALL exibir `Ana`, o texto `20% → 60%`, a data/hora e o
  comentário `Solda dos pontos 1 a 8`

#### Scenario: Lista de contribuidores é distinta e sem repetição

- **WHEN** a tarefa tem 4 avanços, sendo 3 de `Ana` e 1 de `Bruno`
- **THEN** a lista de contribuidores SHALL conter exatamente `Ana` e `Bruno`, uma vez
  cada

#### Scenario: Avanço concluído sem comentário é exibido sem texto vazio enganoso

- **WHEN** existe um avanço de `60 → 100` sem comentário (permitido por §2.4)
- **THEN** a entrada SHALL exibir `60% → 100%` e um marcador explícito de ausência de
  comentário, e NÃO SHALL exibir o comentário de outra entrada no lugar

### Requirement: Exibição de data/hora por recorded_at

O sistema SHALL exibir na timeline o timestamp `recorded_at` — o momento em que a
pessoa agiu — e NÃO SHALL exibir `created_at` (D8).

#### Scenario: Avanço registrado offline exibe o momento da ação

- **WHEN** um avanço tem `recorded_at = 2026-03-10 14:05` e
  `created_at = 2026-03-10 18:40` (sincronizado ao voltar a rede)
- **THEN** a entrada SHALL exibir `10/03/2026 14:05`

#### Scenario: Ordenação usa recorded_at com desempate estável

- **WHEN** dois avanços têm o mesmo `recorded_at = 2026-03-10 14:05` e `created_at`
  `18:40` e `18:41`
- **THEN** a entrada de `created_at 18:41` SHALL aparecer antes da de `18:40`, e a
  ordem SHALL ser idêntica entre recarregamentos

### Requirement: Marcação de entradas legadas

O sistema SHALL identificar visualmente, na timeline, as entradas geradas pela
migração do campo legado `obs` (§3.5, §1.4).

#### Scenario: Entrada legada recebe marcador

- **WHEN** a timeline contém uma entrada com `legacy = true`
- **THEN** a entrada SHALL exibir um marcador textual de origem legada, além do
  comentário

#### Scenario: Entrada normal não recebe marcador

- **WHEN** a timeline contém uma entrada com `legacy = false`
- **THEN** a entrada NÃO SHALL exibir o marcador de origem legada

### Requirement: Modal de atribuição de responsáveis

O sistema SHALL exibir, no modal de atribuição, uma lista de checkboxes com todas as
pessoas do workspace, com os responsáveis atuais da tarefa já marcados, e SHALL
persistir a seleção como o conjunto de responsáveis da tarefa (§3.5, D10).

#### Scenario: Responsáveis atuais chegam marcados

- **WHEN** o workspace tem as pessoas `Ana`, `Bruno` e `Carla`, e a tarefa tem
  `assignees = [Ana, Carla]`
- **THEN** o modal SHALL exibir 3 checkboxes e SHALL marcar `Ana` e `Carla`

#### Scenario: Desmarcar todos deixa a tarefa sem responsável

- **WHEN** o usuário desmarca `Ana` e `Carla` e confirma
- **THEN** a tarefa SHALL ficar com `assignees` vazio, e NÃO SHALL ser criado nenhum
  responsável sentinela chamado `Não Atribuído` (D11)

#### Scenario: Salvar atualiza os chips sem recarregar a página

- **WHEN** o usuário marca `Bruno` e confirma
- **THEN** a célula Responsáveis da linha SHALL passar a exibir os chips `Ana`,
  `Carla` e `Bruno`

### Requirement: Cadastro de pessoa nova a partir do modal

O sistema SHALL oferecer, no modal de atribuição, um campo para cadastrar uma pessoa
nova, que SHALL ser persistida no workspace e SHALL entrar já marcada na seleção
corrente (§3.5, D10).

#### Scenario: Pessoa nova entra marcada e é salva no workspace

- **WHEN** o usuário digita `Daniel` no campo de nova pessoa e aciona adicionar
- **THEN** `Daniel` SHALL aparecer na lista de checkboxes já marcado, e SHALL passar a
  constar na lista de pessoas do workspace ao reabrir o modal em outra tarefa

#### Scenario: Nome duplicado não cria pessoa repetida

- **WHEN** o workspace já tem a pessoa `Ana` e o usuário digita `  ana  ` e aciona
  adicionar
- **THEN** o sistema NÃO SHALL criar uma segunda pessoa, SHALL marcar a `Ana`
  existente e SHALL informar que a pessoa já existe

#### Scenario: Nome em branco é rejeitado

- **WHEN** o usuário aciona adicionar com o campo contendo apenas espaços
- **THEN** nenhuma pessoa SHALL ser criada e o campo SHALL exibir mensagem de
  validação em pt-BR

### Requirement: Restrições por papel nos modais

O sistema SHALL permitir a membros com papel `view` apenas a leitura do histórico, e
SHALL negar a eles a abertura e a submissão do modal de atribuição, com a negação
garantida no servidor (§4.1, §4.1 inv. 1 e 4).

#### Scenario: Membro view abre o histórico mas não a atribuição

- **WHEN** um membro com papel `view` abre a tela do robô e aciona o botão de
  contagem da trilha
- **THEN** o modal de histórico SHALL abrir, e a célula Responsáveis NÃO SHALL ser
  acionável para abrir o modal de atribuição

#### Scenario: Servidor rejeita atribuição feita por membro view

- **WHEN** um membro com papel `view` envia
  `PUT /api/v1/tasks/<id>/assignees` com `person_ids: [<id de Ana>]`
- **THEN** a API SHALL responder `403` e os responsáveis persistidos NÃO SHALL mudar

#### Scenario: Modal de atribuição não lista pessoas de outro workspace

- **WHEN** um usuário do workspace `W1` abre o modal de atribuição e o workspace `W2`
  possui a pessoa `Eduardo`
- **THEN** a lista de checkboxes NÃO SHALL conter `Eduardo`

### Requirement: Acessibilidade e foco dos modais

Os modais SHALL prender o foco enquanto abertos, SHALL fechar com `Esc` devolvendo o
foco ao elemento que os abriu, e SHALL ter os alvos de toque mínimos exigidos
(DESIGN.md §Accessibility, PRODUCT.md).

#### Scenario: Esc fecha e devolve o foco ao gatilho

- **WHEN** o usuário abre o modal de histórico pelo botão de contagem e pressiona
  `Esc`
- **THEN** o modal SHALL fechar e o foco SHALL retornar ao botão de contagem da mesma
  linha

#### Scenario: Checkboxes atendem ao alvo mínimo em mobile

- **WHEN** o modal de atribuição é aberto num viewport de 375px
- **THEN** cada linha de checkbox SHALL ter área acionável de no mínimo 40px de
  altura, com o rótulo fazendo parte do alvo
