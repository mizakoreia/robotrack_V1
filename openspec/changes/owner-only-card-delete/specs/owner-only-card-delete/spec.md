## ADDED Requirements

### Requirement: Controle de excluir nos cards dos três níveis, visível só ao dono

Cada tipo de card de hierarquia — projeto (Visão Geral), célula (Projeto) e robô (Célula) —
SHALL oferecer um controle de excluir ao **dono** do workspace. O controle SHALL ficar
**ausente do DOM** para papéis `edit` e `view` (não apenas desabilitado), espelhando a matriz
owner-only. O servidor permanece a autoridade (403 para não-dono).

#### Scenario: Dono vê excluir em projeto, célula e robô

- **WHEN** o dono abre a Visão Geral, uma tela de Projeto e uma tela de Célula
- **THEN** cada card (projeto, célula, robô) SHALL apresentar um controle de excluir
  (`IconButton` lixeira com rótulo acessível "Excluir <nome>")

#### Scenario: Membro edit não vê excluir em card nenhum (negação)

- **WHEN** um membro `edit` abre as mesmas telas
- **THEN** nenhum card SHALL renderizar o controle de excluir
- **AND** os controles de criar/editar/reordenar SHALL continuar visíveis

#### Scenario: Membro view não vê excluir (negação)

- **WHEN** um membro `view` abre as telas
- **THEN** nenhum card SHALL renderizar o controle de excluir

### Requirement: Excluir card sempre passa por confirmação

Ativar o controle de excluir de qualquer card SHALL abrir um **diálogo de confirmação** que
nomeia o alvo antes de qualquer chamada de exclusão. A exclusão só SHALL ocorrer após a
confirmação explícita. Para célula e robô com filhos, o texto SHALL avisar que a subárvore é
arquivada (o soft-delete cascateia).

#### Scenario: Confirmar exclui; cancelar não

- **WHEN** o dono ativa excluir num card e confirma no diálogo
- **THEN** o cliente SHALL chamar o `DELETE` correspondente e remover o card ao concluir
- **WHEN** o dono cancela
- **THEN** nenhuma chamada de exclusão SHALL ocorrer

#### Scenario: Robô ganha caminho de exclusão

- **WHEN** o dono exclui um robô a partir do card de robô
- **THEN** o cliente SHALL usar um hook de exclusão de robô ligado a `DELETE
  /api/v1/robots/:id`, invalidando apenas a chave de robôs da célula (nunca o tenant inteiro)

### Requirement: Excluir tarefa é owner-only; editar a tarefa segue owner+edit

Na tabela de tarefas do robô (`AcoesCell`), o controle de **excluir** (lixeira) SHALL ser
visível apenas ao **dono**; o controle de **editar** a descrição SHALL permanecer visível a
`owner` e `edit`. O servidor SHALL ser a autoridade (`DELETE /api/v1/tasks/:id` responde 403
para `edit`). O swipe-to-reveal NÃO SHALL ser aplicado às tarefas (a tarefa vive numa
tabela/cartão, não num `EntityCard`).

#### Scenario: Dono vê excluir e editar na tarefa

- **WHEN** o dono abre a tabela de tarefas de um robô
- **THEN** cada linha/cartão de tarefa SHALL apresentar excluir (lixeira) e editar (descrição)

#### Scenario: Membro edit vê editar mas NÃO excluir na tarefa (negação)

- **WHEN** um membro `edit` abre a tabela de tarefas
- **THEN** cada tarefa SHALL apresentar o controle de editar a descrição
- **AND** NÃO SHALL apresentar o controle de excluir a tarefa

#### Scenario: Excluir tarefa exige confirmação

- **WHEN** o dono ativa excluir numa tarefa
- **THEN** a exclusão SHALL passar por confirmação antes de chamar `DELETE /api/v1/tasks/:id`

### Requirement: Swipe-to-reveal excluir no mobile com alternativa acessível

No viewport de toque/estreito, arrastar um card de hierarquia para o lado SHALL revelar uma
ação **Excluir**. O gesto SHALL ser um atalho de conveniência e NÃO SHALL ser o único caminho
para excluir: o controle de excluir por teclado/leitor de tela (`IconButton`) SHALL permanecer
disponível ao dono. Tocar a ação revelada SHALL abrir o diálogo de confirmação (nunca excluir
direto). O gesto SHALL respeitar `prefers-reduced-motion` (sem animação), usar `touch-pan-y`
(rolagem vertical não dispara o swipe) e não SHALL disparar a navegação do card
(`role=button`). A ação revelada SHALL ter alvo de toque ≥ 40px e usar a cor de status `danger`.

#### Scenario: Arrastar revela excluir; tocar confirma

- **WHEN** o dono arrasta um card horizontalmente além do limiar no mobile
- **THEN** a ação Excluir SHALL ser revelada
- **AND** tocar nela SHALL abrir o diálogo de confirmação (não excluir imediatamente)

#### Scenario: Rolar a página não revela excluir

- **WHEN** o usuário arrasta predominantemente na vertical (rolagem)
- **THEN** o card NÃO SHALL revelar a ação e a página SHALL rolar normalmente

#### Scenario: Teclado e leitor de tela têm o mesmo poder (sem depender do gesto)

- **WHEN** o dono navega por teclado ou leitor de tela
- **THEN** o controle de excluir SHALL ser alcançável e operável sem nenhum gesto de swipe

#### Scenario: Movimento reduzido zera a animação do swipe

- **WHEN** o usuário tem `prefers-reduced-motion: reduce`
- **THEN** a revelação SHALL ser instantânea, sem transição, sem bounce/elastic

#### Scenario: Swipe não abre o card

- **WHEN** o dono arrasta o card para revelar a ação
- **THEN** a navegação "Abrir <nome>" do card NÃO SHALL ser disparada pelo arrasto
