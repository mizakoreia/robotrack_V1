## ADDED Requirements

### Requirement: Progresso não é editável diretamente

A interface SHALL tratar o progresso como valor somente-leitura fora do modal "Registrar
avanço" (§2.4). Nenhum controle da tela do robô, de "Minhas Tarefas" ou de qualquer
formulário de edição de tarefa MUST persistir progresso sem passar pelo modal.

#### Scenario: Não existe campo de progresso no formulário de edição de tarefa

- **WHEN** o usuário abre "Editar descrição" de uma tarefa em `progress = 45`
- **THEN** o formulário expõe descrição, categoria e peso, e nenhum campo de progresso
- **AND** salvar o formulário não altera `progress` nem `status`

#### Scenario: Soltar o slider não persiste sozinho

- **WHEN** o usuário arrasta o slider de `45` para `60` e solta
- **THEN** nenhuma requisição de escrita é emitida
- **AND** o modal "Registrar avanço" abre com `de 45%` → `para 60%`

### Requirement: Gatilhos do modal calculam o valor a partir do estado atual

Os gatilhos SHALL ser: soltar o slider (passo `5`) e os botões `−10` / `+10`. O valor
"para" MUST ser calculado a partir do progresso corrente lido do cache de servidor da
tarefa no instante do clique, nunca de um valor capturado em closure no render. O
resultado MUST sofrer clamp em `[0, 100]`.

#### Scenario: Dois +10 seguidos sem recarregar produzem +20

- **WHEN** a tarefa está em `45` e o usuário clica `+10`, confirma o modal, e clica `+10`
  novamente sem recarregar a página
- **THEN** o primeiro modal abre com `para 55` e o segundo com `para 65`
- **AND** a tarefa termina em `progress = 65`, não `55`

#### Scenario: +10 em 95 sofre clamp em 100

- **WHEN** a tarefa está em `95` e o usuário clica `+10`
- **THEN** o modal abre com `para 100`
- **AND** o campo de comentário é apresentado como opcional

#### Scenario: −10 em 5 sofre clamp em 0

- **WHEN** a tarefa está em `5` e o usuário clica `−10`
- **THEN** o modal abre com `para 0`
- **AND** o comentário é obrigatório

#### Scenario: Slider anda de 5 em 5

- **WHEN** o usuário arrasta o slider de uma tarefa em `45`
- **THEN** os valores alcançáveis são `45`, `50`, `55`, … e nunca `47`

#### Scenario: Avanço de outra pessoa em tempo real muda a base do próximo clique

- **WHEN** a tarefa está em `45`, outra sessão registra `45 → 70`, o evento do
  `WorkspaceChannel` invalida a query key, e o usuário então clica `+10`
- **THEN** o modal abre com `de 70%` → `para 80%`

### Requirement: Conteúdo e regra de comentário do modal

O modal SHALL exibir a descrição da tarefa, o progresso `de` (atual, somente leitura) e
`para` (novo, editável), e um campo de comentário. Quando o valor `para` for `< 100`, o
comentário MUST ser obrigatório e o rótulo MUST ser "O que você fez? O que falta?". Quando
for `100`, o comentário MUST ser opcional e o rótulo MUST ser "O que você fez? (opcional ao
concluir)". Os rótulos MUST vir do módulo único de strings pt-BR (D14).

#### Scenario: Rótulo e obrigatoriedade mudam ao editar o campo "para"

- **WHEN** o modal está aberto com `para 60` e o usuário altera o campo para `100`
- **THEN** o rótulo passa a "O que você fez? (opcional ao concluir)"
- **AND** o botão de confirmar fica habilitado com o comentário vazio

#### Scenario: Confirmar bloqueado sem comentário abaixo de 100

- **WHEN** o modal está aberto com `de 45%` → `para 60%` e o comentário está vazio
- **THEN** o botão de confirmar está desabilitado
- **AND** o campo de comentário exibe o estado de obrigatório com `aria-required="true"`

#### Scenario: Comentário só com espaços não habilita o confirmar

- **WHEN** o usuário digita três espaços no comentário com `para 60`
- **THEN** o botão de confirmar permanece desabilitado

### Requirement: Confirmação envia o avanço com uuid e recorded_at do cliente

Ao confirmar, a interface SHALL emitir `POST /api/v1/tasks/:task_id/advances` com `id`
uuid gerado no cliente (D1), `recorded_at` do instante da confirmação (D8),
`from_progress`, `to_progress`, `comment` e o `lock_version` da tarefa lido quando o modal
abriu. Após o sucesso, SHALL invalidar as query keys
`['ws', wsId, 'robot', robotId, 'tasks']` e `['ws', wsId, 'task', taskId, 'advances']`.

#### Scenario: Confirmação envia o instante da ação, não o da rede

- **WHEN** o usuário confirma às `14:00` sem conectividade e a fila offline drena às `17:05`
- **THEN** o corpo enviado carrega `recorded_at = 14:00`
- **AND** a trilha exibe `14:00` após a sincronização

#### Scenario: Duplo clique no confirmar não cria duas entradas

- **WHEN** o usuário clica duas vezes no botão de confirmar em menos de 300 ms
- **THEN** o mesmo `uuid` é enviado nas duas requisições
- **AND** a trilha da tarefa ganha exatamente 1 entrada nova

### Requirement: Cancelar reverte o slider ao valor persistido

Cancelar o modal SHALL descartar o rascunho e SHALL devolver o slider e a leitura em `%` ao
valor persistido no servidor. Um arraste não confirmado MUST NOT ter efeito algum.

#### Scenario: Arrastar para 60 e cancelar devolve o slider a 45

- **WHEN** a tarefa está em `45`, o usuário arrasta o slider até `60`, o modal abre, e ele
  cancela
- **THEN** o slider volta a exibir `45`
- **AND** a leitura em `%` da linha exibe `45%`
- **AND** nenhuma requisição de escrita foi emitida

#### Scenario: Fechar pelo Esc equivale a cancelar

- **WHEN** o modal está aberto com `para 60` e o usuário pressiona `Esc`
- **THEN** o slider volta ao valor persistido
- **AND** o foco retorna ao controle que abriu o modal

#### Scenario: Cancelar após 422 do servidor também reverte

- **WHEN** o envio falha com `422` e o usuário cancela em vez de corrigir
- **THEN** o slider volta ao valor persistido
- **AND** nenhum estado de rascunho permanece ao reabrir o modal

### Requirement: Tratamento de conflito 409 na interface

Ao receber `409`, a interface MUST NOT descartar o comentário digitado e MUST NOT reenviar
automaticamente. SHALL exibir o autor, o valor e o horário do avanço concorrente e oferecer
duas ações: recalcular o mesmo delta a partir do novo valor — gerando **novo uuid** — ou
descartar.

#### Scenario: 409 preserva o comentário e mostra quem mudou

- **WHEN** o usuário escreve "Ajustei o TCP da tocha", confirma `45 → 60`, e recebe `409`
  informando que `Ana` registrou `70`
- **THEN** o comentário digitado continua no campo
- **AND** o modal informa que `Ana` registrou `70%` com o horário `recorded_at` dela

#### Scenario: Recalcular a partir do novo valor gera novo uuid

- **WHEN** o usuário escolhe "Recalcular a partir de 70%" após o `409` de um `+10`
- **THEN** o modal passa a `de 70%` → `para 80%`
- **AND** o `uuid` enviado na nova confirmação é diferente do da tentativa que recebeu `409`

#### Scenario: 409 não é tratado como erro de rede

- **WHEN** a resposta `409` chega
- **THEN** a mutation não entra em política de retentativa automática
- **AND** nenhum toast genérico de "erro de conexão" é exibido

### Requirement: Interface de somente leitura para membro view

Para membro com papel `view`, a interface SHALL ocultar os botões `−10` / `+10`, desabilitar
o slider e o seletor de status, e MUST NOT abrir o modal. O bloqueio na interface é
conveniência; a negação de servidor (§4.1 inv. 1) permanece a garantia.

#### Scenario: Membro view não consegue abrir o modal

- **WHEN** um membro `view` visualiza a tabela de tarefas do robô
- **THEN** os botões `−10` / `+10` não são renderizados
- **AND** o slider está desabilitado com `aria-disabled="true"`
- **AND** clicar na leitura de progresso não abre o modal

#### Scenario: Bloqueio da interface removido não produz escrita

- **WHEN** um membro `view` remove o atributo `disabled` pelo devtools e força o envio do
  avanço
- **THEN** a API responde `403`
- **AND** a interface exibe a mensagem pt-BR de permissão insuficiente e recarrega a tarefa
