## ADDED Requirements

### Requirement: Tela única de login e cadastro com alternância

O sistema SHALL apresentar em `/entrar` um formulário único que alterna entre
login e cadastro (§3.1), exibindo o campo **nome** somente no modo cadastro e
exigindo-o ali, e SHALL preservar o e-mail já digitado ao alternar entre os modos.

#### Scenario: Modo login não pede nome

- **WHEN** a tela abre em `/entrar` no modo login
- **THEN** há exatamente os campos e-mail, senha, o checkbox "manter conectado" e o botão "Entrar com Google", e nenhum campo de nome está no documento

#### Scenario: Alternar para cadastro revela o nome

- **WHEN** o usuário clica em "Criar conta"
- **THEN** o campo "Nome" aparece, fica marcado como obrigatório e recebe o foco

#### Scenario: E-mail sobrevive à alternância

- **WHEN** o usuário digita `ana@fabrica.com` no modo login e alterna para cadastro
- **THEN** o campo de e-mail ainda contém `ana@fabrica.com`

#### Scenario: Cadastro sem nome não envia

- **WHEN** o usuário submete o cadastro com nome vazio e os demais campos preenchidos
- **THEN** nenhuma requisição `POST /auth/v1/registration` é disparada e a mensagem de erro é anunciada por `aria-live` no campo Nome

### Requirement: Validação de senha no cliente espelha o servidor

O sistema SHALL bloquear no cliente o envio de senha com menos de 6 caracteres
(§3.1) e SHALL exibir no campo correspondente os erros 422 devolvidos pelo
servidor, sem substituí-los por uma mensagem genérica.

#### Scenario: Senha de 5 caracteres não é enviada

- **WHEN** o usuário submete o cadastro com a senha `"abcde"`
- **THEN** nenhuma requisição de rede é feita e a mensagem indica o mínimo de 6 caracteres

#### Scenario: Erro do servidor aparece no campo certo

- **WHEN** o servidor responde 409 para e-mail já cadastrado
- **THEN** a mensagem é exibida junto ao campo de e-mail e o campo de senha permanece preenchido

#### Scenario: Credenciais inválidas no login

- **WHEN** o servidor responde 401 no login
- **THEN** a tela mostra "E-mail ou senha inválidos.", limpa apenas o campo de senha e não redireciona

### Requirement: "Manter conectado" escolhe o meio de armazenamento

O checkbox "manter conectado" SHALL determinar onde a sessão é persistida:
`localStorage` quando marcado (sobrevive ao reinício do navegador),
`sessionStorage` quando desmarcado (some ao fechar a aba) — §3.1, §4.2 — e SHALL
ser enviado ao servidor como `remember_me` para definir também o `exp` do token.

#### Scenario: Marcado persiste entre reinícios

- **WHEN** o login é feito com "manter conectado" marcado e a aplicação é recarregada do zero
- **THEN** a sessão é restaurada de `localStorage` e o usuário cai direto na aplicação, sem passar por `/entrar`

#### Scenario: Desmarcado morre com a aba

- **WHEN** o login é feito com "manter conectado" desmarcado
- **THEN** o token é gravado em `sessionStorage` e `localStorage` NÃO contém chave alguma com o token; uma nova aba abre em `/entrar`

#### Scenario: O checkbox chega ao servidor

- **WHEN** o login é feito com "manter conectado" marcado
- **THEN** o corpo de `POST /auth/v1/session` contém `remember_me: true`

#### Scenario: Trocar de modo limpa o armazenamento anterior

- **WHEN** um usuário com sessão em `localStorage` faz logout e loga de novo com "manter conectado" desmarcado
- **THEN** `localStorage` não contém resíduo da sessão antiga e o token novo está apenas em `sessionStorage`

### Requirement: Timeout de segurança quando o armazenamento está bloqueado

O login SHALL NÃO travar quando o navegador bloqueia `localStorage` ou
`sessionStorage` (§3.1): toda leitura/escrita SHALL estar protegida contra
exceção, o handshake com o armazenamento SHALL correr contra um timeout de
1500 ms e, esgotado o prazo, o fluxo SHALL prosseguir com armazenamento em
memória e avisar o usuário.

#### Scenario: Storage lança exceção

- **WHEN** `localStorage.setItem` lança `QuotaExceededError` (modo privado) durante o login bem-sucedido
- **THEN** o usuário é levado à aplicação normalmente e um toast informa que a sessão não vai persistir

#### Scenario: Storage pendura além do timeout

- **WHEN** o acesso ao armazenamento não resolve em 1500 ms
- **THEN** o fluxo segue com storage em memória, o toast de aviso aparece, e a navegação para a aplicação ocorre — o botão de entrar não fica em estado de carregamento indefinido

#### Scenario: Recarregar com storage bloqueado volta para o login

- **WHEN** a sessão está apenas em memória e o usuário recarrega a página
- **THEN** a aplicação abre em `/entrar` sem erro de console e sem tela em branco

### Requirement: Token de convite capturado antes do login

O sistema SHALL, ao abrir `/convite/:token` sem sessão, gravar o token em
`sessionStorage` sob `robotrack.invite_token` **antes** de redirecionar para
`/entrar` (§3.1, §4.2), e SHALL consumi-lo logo após a autenticação, chamando o
endpoint de aceite de `workspace-invitations`.

#### Scenario: Convite guardado antes do login

- **WHEN** um visitante sem sessão abre `/convite/abc123`
- **THEN** `sessionStorage["robotrack.invite_token"] == "abc123"` e a navegação vai para `/entrar`

#### Scenario: Convite consumido logo após autenticar

- **WHEN** esse visitante conclui o cadastro com sucesso
- **THEN** o aceite do convite `abc123` é chamado uma única vez, a chave `robotrack.invite_token` é removida, e o usuário entra no workspace do convite

#### Scenario: Convite inválido ou expirado não bloqueia a entrada

- **WHEN** o aceite responde 410 (convite expirado — 7 dias, §3.10)
- **THEN** a chave é removida, um aviso explica que o convite expirou, e o usuário permanece autenticado na aplicação em vez de ficar preso numa tela de erro

#### Scenario: Usuário já autenticado abre o link do convite

- **WHEN** um usuário com sessão ativa abre `/convite/abc123`
- **THEN** o aceite é chamado direto, sem passar por `/entrar` e sem gravar nada em `sessionStorage`

#### Scenario: Convite não é reconsumido em recarga

- **WHEN** o convite já foi consumido e o usuário recarrega a aplicação
- **THEN** nenhuma chamada de aceite é disparada, porque a chave já não existe

### Requirement: O convite sobrevive ao redirect de página inteira do Google

O sistema SHALL manter o token de convite disponível através das duas navegações
de página inteira do fluxo OAuth (ida ao Google e volta ao callback), e quando
isso for impossível — armazenamento bloqueado — SHALL detectar a perda e orientar
o usuário, jamais descartando o convite em silêncio.

#### Scenario: Google com convite pendente

- **WHEN** o visitante abre `/convite/abc123`, clica em "Entrar com Google" e volta autenticado pelo callback
- **THEN** o token `abc123` ainda está em `sessionStorage`, o aceite é chamado e a chave é removida

#### Scenario: Storage bloqueado perde o convite no redirect

- **WHEN** `sessionStorage` está bloqueado, o visitante entra por `/convite/abc123`, autentica pelo Google e retorna
- **THEN** a aplicação detecta que a origem da entrada era um convite mas não há token guardado e exibe a instrução de reabrir o link do convite, agora já autenticado — em vez de entrar sem workspace e sem explicação

#### Scenario: Login por senha não perde o convite

- **WHEN** o visitante entra por `/convite/abc123` e autentica por e-mail e senha, sem sair da página
- **THEN** o token vem do armazenamento em memória se `sessionStorage` estiver bloqueado, e o aceite ocorre normalmente

### Requirement: Callback do OAuth lê o fragmento e o apaga da URL

O sistema SHALL ler o token do fragmento em `/auth/callback`, gravá-lo conforme o
"manter conectado" escolhido antes do redirect, e SHALL apagar o fragmento da
barra de endereço com `history.replaceState` antes de qualquer navegação.

#### Scenario: Fragmento é consumido e removido

- **WHEN** o navegador chega em `/auth/callback#access_token=eyJ…&expires_at=…`
- **THEN** a sessão é estabelecida e `window.location.hash` fica vazio, de modo que copiar a URL da barra ou voltar no histórico não expõe o token

#### Scenario: Callback com erro

- **WHEN** o navegador chega em `/auth/callback#error=acesso_negado`
- **THEN** a aplicação volta para `/entrar` com a mensagem de que o acesso pelo Google foi negado, e nenhuma sessão é criada

#### Scenario: Callback sem fragmento

- **WHEN** `/auth/callback` é aberto diretamente, sem fragmento
- **THEN** a aplicação redireciona para `/entrar` sem lançar exceção

### Requirement: Fonte única do token no cliente

O token SHALL ter um único dono no cliente (`authStore`), e o cliente HTTP SHALL
lê-lo desse store — não de `localStorage` diretamente. A duplicação
`localStorage['token']` + `auth-storage` do template é removida.

#### Scenario: Nenhuma leitura direta de storage no cliente HTTP

- **WHEN** o código de `lib/api/client.ts` é inspecionado
- **THEN** não há referência a `localStorage.getItem('token')`; o header `Authorization` é montado a partir de `useAuthStore.getState().accessToken`

#### Scenario: Token atualizado após renovação chega no próximo request

- **WHEN** a renovação devolve um token novo e o store é atualizado
- **THEN** a requisição seguinte já usa o token novo, sem recarregar a página

### Requirement: Logout e expiração limpam a sessão sem laço

O logout SHALL chamar `DELETE /auth/v1/session`, limpar `localStorage`,
`sessionStorage`, o store e o cache do React Query, e redirecionar para `/entrar`.
Um 401 em qualquer requisição SHALL encerrar a sessão em vez de tentar renovação
transparente.

#### Scenario: Logout limpo

- **WHEN** o usuário clica em "Sair"
- **THEN** `DELETE /auth/v1/session` é chamado, os dois storages ficam sem chave de sessão, o cache do React Query é esvaziado e a rota vira `/entrar`

#### Scenario: Logout com a rede fora

- **WHEN** o usuário clica em "Sair" e `DELETE /auth/v1/session` falha por rede
- **THEN** o estado local é limpo mesmo assim e o usuário chega em `/entrar` — a sessão local nunca fica presa por causa do servidor

#### Scenario: 401 encerra em vez de entrar em laço

- **WHEN** uma chamada de domínio responde 401 porque o token foi revogado em outro dispositivo
- **THEN** a sessão é encerrada, a rota vira `/entrar` com o aviso de sessão expirada, e nenhuma tentativa de renovação é disparada — no máximo uma requisição de auth é feita em resposta a esse 401

#### Scenario: Dados do workspace anterior não sobrevivem à troca de usuário

- **WHEN** o usuário A faz logout e o usuário B loga na mesma aba
- **THEN** nenhuma query em cache do usuário A é servida a B, porque o cache do React Query foi esvaziado no logout
