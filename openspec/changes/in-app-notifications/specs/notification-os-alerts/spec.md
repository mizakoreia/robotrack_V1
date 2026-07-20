## ADDED Requirements

### Requirement: Permissão pedida por gesto explícito

O sistema SHALL solicitar permissão da Notification API somente em resposta a um
clique explícito do usuário no centro de notificações, e SHALL nunca chamar
`Notification.requestPermission()` durante a carga da página.

#### Scenario: Nenhuma solicitação de permissão no load

- **WHEN** o app é carregado com `Notification.permission === 'default'`
- **THEN** `Notification.requestPermission` NÃO é invocado
- **AND** o centro de notificações exibe o controle "Ativar alertas do sistema"

#### Scenario: Permissão negada não gera tentativa de alerta

- **WHEN** `Notification.permission === 'denied'` e chegam 3 notificações novas
- **THEN** `new Notification(...)` NÃO é construído nenhuma vez
- **AND** as 3 aparecem normalmente na lista e no badge

### Requirement: Alerta do SO apenas para itens novos

O sistema SHALL disparar alerta do sistema operacional exclusivamente para
notificações cujo `recorded_at` seja maior que a marca d'água de sessão, e a
marca d'água SHALL ser inicializada — sem disparar nada — pela primeira resposta
de listagem de cada sessão. A marca d'água SHALL viver em memória, nunca em
`localStorage` ou `sessionStorage`.

#### Scenario: Recarregar com 10 não lidas antigas dispara zero alertas

- **WHEN** a pessoa tem 10 notificações com `read = false` e `recorded_at` de
  ontem, e recarrega a página com `Notification.permission === 'granted'`
- **THEN** exatamente 0 alertas do sistema operacional são disparados
- **AND** o badge exibe `10`

#### Scenario: Notificação chegada após a carga dispara alerta

- **WHEN** a marca d'água já foi inicializada e chega uma notificação com
  `recorded_at` posterior a ela, com a aba em segundo plano e permissão concedida
- **THEN** exatamente 1 alerta do sistema operacional é disparado
- **AND** a marca d'água avança para esse `recorded_at`

#### Scenario: Item novo não dispara duas vezes

- **WHEN** a mesma notificação chega duas vezes (evento em tempo real seguido de
  refetch da listagem)
- **THEN** exatamente 1 alerta é disparado

#### Scenario: Marca d'água não sobrevive ao reload

- **WHEN** a pessoa fica 2 dias sem abrir o app, recebe 40 notificações no
  intervalo e então abre o app
- **THEN** exatamente 0 alertas do sistema operacional são disparados

#### Scenario: Aba visível suprime o alerta do SO

- **WHEN** chega uma notificação nova com `document.visibilityState === 'visible'`
- **THEN** nenhum alerta do sistema operacional é disparado
- **AND** o feedback in-app (badge e lista) é atualizado

#### Scenario: Um único ponto de construção de alerta

- **WHEN** o repositório do frontend é varrido por `new Notification(`
- **THEN** a única ocorrência fora de testes está no hook
  `useOsNotificationAlerts`
- **AND** a regra de lint que proíbe as demais está ativa no CI

### Requirement: Clique no alerta foca o app e navega por ctx

O sistema SHALL, ao clique no alerta do sistema operacional, focar a janela do
app e navegar até o robô da tarefa usando o `ctx` da notificação.

#### Scenario: Clique navega para o robô da tarefa

- **WHEN** a pessoa clica num alerta cuja notificação tem
  `ctx = {pid: P1, cid: C1, rid: R1, tid: T1}`
- **THEN** `window.focus()` é chamado
- **AND** a rota resultante é a tela do robô `R1` com a tarefa `T1` destacada

#### Scenario: Clique com ctx incompleto cai no centro de notificações

- **WHEN** a pessoa clica num alerta cuja notificação tem `ctx_robot_id` nulo
- **THEN** o app é focado e a navegação leva ao centro de notificações com aviso
  de contexto indisponível, nunca a uma rota inválida

#### Scenario: Alerta de notificação de outro workspace troca de contexto antes de navegar

- **WHEN** a pessoa está no workspace A e clica num alerta de notificação do
  workspace B
- **THEN** o app troca para o workspace B antes de navegar, descartando o estado
  do workspace A conforme `app-shell-navigation`
