## ADDED Requirements

### Requirement: Porta descobrível e sempre acessível para entrar por código estando autenticado

O sistema SHALL oferecer, na área autenticada, um ponto de entrada descobrível para
"Entrar em outro workspace com código", disponível no **menu da conta** (o card de usuário
no rodapé da sidebar). Esse ponto de entrada MUST estar acessível independentemente do
número de workspaces do usuário — inclusive quando o usuário possui **exatamente um**
workspace. O sistema MUST NOT depender do seletor de workspace como porta primária, pois o
seletor só existe com mais de um workspace.

#### Scenario: Usuário com um único workspace enxerga a porta

- **WHEN** um usuário autenticado cujo índice de workspaces contém apenas o próprio
  workspace abre o menu da conta
- **THEN** o menu SHALL conter um item rotulado "Entrar em outro workspace com código"
- **AND** o seletor de workspace NÃO SHALL estar renderizado como controle (só há 1
  workspace), comprovando que a porta não depende dele

#### Scenario: Acionar o item abre o diálogo de entrada por código

- **WHEN** o usuário escolhe o item "Entrar em outro workspace com código" no menu da conta
- **THEN** o sistema SHALL abrir o diálogo de entrada por código
- **AND** o menu da conta SHALL fechar

#### Scenario: O rótulo do item vem do dicionário de convites

- **WHEN** o item de menu é renderizado
- **THEN** seu texto SHALL ser resolvido a partir de `lib/i18n/invitations.ts` (nenhum
  literal de convite hardcoded fora desse módulo, conforme a regra de CI existente)

#### Scenario: Nome acessível único na tela (regra G)

- **WHEN** o menu da conta e a topbar coexistem numa tela onde o atalho "Convidar pessoa"
  está presente
- **THEN** o nome acessível "Entrar em outro workspace com código" SHALL ser distinto de
  "Convidar pessoa" e de "Equipe e convites" — dois controles de mesmo nome acessível na
  mesma tela seriam defeito

### Requirement: Diálogo usa o e-mail da sessão e pede apenas o código

O diálogo de entrada por código SHALL exibir o e-mail da sessão como contexto
somente-leitura e SHALL oferecer um único campo editável, o Código, com máscara `XXXX-XXXX`
e normalização tolerante (maiúsculas, remoção de hífen/espaço, mapeamento de ambíguos). O
sistema MUST NOT oferecer campo de e-mail editável no diálogo in-app, e no aceite SHALL
usar o e-mail autenticado da sessão.

#### Scenario: Diálogo mostra o e-mail da sessão e um só campo

- **WHEN** o diálogo é aberto por um usuário autenticado com e-mail `joao@fabrica.com`
- **THEN** o diálogo SHALL exibir "joao@fabrica.com" como contexto somente-leitura
- **AND** SHALL apresentar exatamente um campo editável, o Código
- **AND** NÃO SHALL apresentar nenhum campo de e-mail editável

#### Scenario: Máscara e normalização toleram a digitação de galpão

- **WHEN** o usuário digita `4k7p 9qmx` no campo de código
- **THEN** o campo SHALL exibir `4K7P-9QMX`
- **AND** o valor enviado no aceite SHALL ser o código normalizado `4K7P9QMX`

#### Scenario: Submeter usa o e-mail da sessão, não um digitado

- **WHEN** o usuário `joao@fabrica.com` submete um código válido no diálogo
- **THEN** o aceite SHALL ser disparado com o par (código, `joao@fabrica.com`), sendo o
  e-mail o da sessão autenticada

### Requirement: Aceite in-app reusa o consumo por código e troca para o novo workspace

O sistema SHALL, no submit do diálogo, consumir o convite reusando o mesmo caminho de aceite
por código já existente (`consumeInviteByCode`), que executa o aceite atômico no servidor
(invariante 6, §4.1). No sucesso, o sistema SHALL trocar o contexto para o workspace
recém-ingressado (via `selectWorkspace`), fechar o diálogo e navegar para a Visão Geral
(`/`). O sistema MUST NOT reimplementar a lógica de aceite nem o mapa de erros.

#### Scenario: Aceite bem-sucedido troca de workspace e navega

- **WHEN** um usuário autenticado submete no diálogo o código válido de um convite `edit`
  pendente do workspace "Linha 3", emitido para o e-mail da sessão
- **THEN** o servidor SHALL responder `200` e criar a `Membership` `edit`
- **AND** o contexto corrente SHALL passar a ser "Linha 3" (via `selectWorkspace`)
- **AND** o diálogo SHALL fechar e a rota corrente SHALL passar a ser `/`

#### Scenario: A troca de workspace descarta o cache do workspace anterior

- **WHEN** o aceite bem-sucedido leva à troca para "Linha 3"
- **THEN** a troca SHALL passar pelo mesmo descarte total de cache do fluxo de troca
  (`switchWorkspace`/`selectWorkspace`), sem invalidação seletiva, de modo que nenhum dado
  do workspace anterior permaneça exibido

#### Scenario: Papel da membership vem do servidor, nunca do cliente

- **WHEN** o aceite in-app ocorre para um convite `view`
- **THEN** a `Membership` SHALL ter `role = "view"` lido pelo servidor dentro da transação,
  e o diálogo SHALL NOT enviar `role` no corpo

### Requirement: Estados de erro nomeados no diálogo in-app

O diálogo SHALL apresentar mensagens específicas por modo de falha, reusando o mapa de erros
existente do aceite por código, e MUST NOT reduzir um erro nomeado ao genérico "não foi
possível aceitar". Em particular, o caso de e-mail do convite divergente do e-mail
autenticado SHALL orientar o usuário de forma específica.

#### Scenario: Convite emitido para outro e-mail orienta a conta correta

- **WHEN** um usuário autenticado como `ana@fabrica.com` submete um código de um convite
  emitido para `joao@fabrica.com`
- **THEN** o sistema NÃO SHALL conceder acesso
- **AND** o diálogo SHALL exibir orientação específica de que o convite foi emitido para
  outro e-mail (sair e entrar com a conta correta, ou pedir um convite para o e-mail atual),
  e NÃO SHALL exibir o erro genérico

#### Scenario: Código travado mostra mensagem própria

- **WHEN** o aceite responde `423 invitation_code_locked`
- **THEN** o diálogo SHALL orientar a pedir um novo código ao responsável, e NÃO SHALL
  exibir o erro genérico

#### Scenario: Código expirado lembra que o link pode valer

- **WHEN** o aceite responde com código expirado (o link do mesmo convite pode continuar
  válido)
- **THEN** o diálogo SHALL exibir mensagem de código expirado, distinta do genérico

#### Scenario: Par inválido responde de forma genérica e sem vazar

- **WHEN** o usuário submete um código inexistente ou que não casa o par
- **THEN** o diálogo SHALL exibir a mensagem genérica de par inválido, sem revelar
  workspace, papel ou e-mail de terceiros

#### Scenario: Sem rede, o diálogo pede conexão em vez de tentar

- **WHEN** o usuário submete o código estando offline
- **THEN** o sistema SHALL exibir a orientação "conecte-se para aceitar" (herdada do
  consumo por código) e NÃO SHALL enfileirar o aceite

### Requirement: Diálogo acessível e com alvo de toque de luva

O diálogo SHALL usar fundo temático nos campos (regra F: campo nativo sem fundo temático é
defeito), alvo de toque ≥ 32px nos controles, foco preso em ciclo com `Esc` devolvendo o
foco ao gatilho, e anúncio de erro por região `aria-live`. O sistema MUST NOT introduzir
token, primitivo, motion ou ban novo (reuso puro do sistema visual existente).

#### Scenario: Campo de código tem fundo temático no escuro

- **WHEN** o diálogo é renderizado no tema escuro
- **THEN** o campo de código SHALL usar fundo temático (não branco-sobre-branco) e passar no
  contraste medido no CI

#### Scenario: Esc fecha o diálogo e devolve o foco ao gatilho

- **WHEN** o diálogo está aberto a partir do item do menu da conta e o usuário pressiona
  `Escape`
- **THEN** o diálogo SHALL fechar e o foco SHALL retornar ao gatilho que o abriu

#### Scenario: Erro é anunciado a leitor de tela

- **WHEN** o aceite falha e a mensagem de erro é exibida
- **THEN** a mensagem SHALL estar numa região `aria-live` para anúncio por leitor de tela

### Requirement: Nenhuma superfície de backend nova

O sistema SHALL atender este fluxo reusando exclusivamente o endpoint autenticado já
existente `POST /api/v1/invitations/code/accept`. Esta capacidade MUST NOT adicionar rota,
endpoint, coluna, índice, policy, throttle, entrada de allowlist ou migration, e MUST NOT
alterar as varreduras de autorização/tenant.

#### Scenario: O aceite in-app usa o endpoint existente

- **WHEN** o diálogo submete um código
- **THEN** a requisição SHALL ser `POST /api/v1/invitations/code/accept` (o mesmo do aceite
  por código já entregue), sem nenhuma rota nova

#### Scenario: As varreduras de autorização e tenant não mudam

- **WHEN** a suíte de varreduras (route-sweep de policy, cross-tenant, tenant-sweep) roda
  após esta change
- **THEN** o conjunto de rotas coberto SHALL ser idêntico ao anterior a esta change (nenhuma
  rota nova a declarar)
