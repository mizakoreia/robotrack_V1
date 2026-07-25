## Why

A ESPECIFICACAO.md §3.10 trata o convite como o caminho para uma segunda pessoa entrar
num workspace; `workspace-invitations` entregou o **link** e `invite-by-code` (26ª change)
entregou o **código curto** `XXXX-XXXX` — hoje digitável **apenas na tela de entrada**
(`/entrar`), numa seção recolhível "Tenho um código de convite" (`AuthPage.tsx`).

O atrito real (levantado pelo dono usando a demo): **quem já está autenticado não passa
pela tela de entrada e, portanto, não tem onde aplicar um código.** O dono do demo — e
qualquer membro existente — só chega ao campo de código **deslogando** primeiro. É um
beco: a pessoa tem uma conta viva, recebeu um código para colaborar noutro workspace, e
o produto a obriga a sair da própria sessão para usá-lo. Contradiz o princípio de produto
"cada pixel serve a uma tarefa" (PRODUCT.md §5) — a tarefa "juntar-se a outro workspace"
existe e não tem porta.

O valor é de **fluência de primeiro uso**: um caminho claro e descobrível, DENTRO do app,
para "entrar em outro workspace com código" estando logado. Isso importa exatamente para o
usuário-alvo (PRODUCT.md): o engenheiro no chão de fábrica que recebe o código por
mensagem já com o app aberto, e prefere digitar um código curto a deslogar e relogar.

Ponto de partida do design: **o motor já existe e não muda.** O aceite por código
autenticado (`POST /api/v1/invitations/code/accept`) é do `invite-by-code`; no frontend,
`consumeInviteByCode(code, email)` já limpa o par, checa offline, chama a API, no sucesso
faz `selectWorkspace(workspace_id)` e emite o toast, e já compartilha o mapa de erros do
`consumeInvite`. O ramo autenticado inteiro já vive em `AuthPage.onSubmitCode` (`if
(isAuthenticated) await consumeInviteByCode(...)`). Esta change **não reimplementa nada
disso** — ela apenas **AFLORA** o mesmo fluxo num ponto acessível ao usuário logado. É
sobretudo FRONTEND/UX + fiação de navegação.

Traduzindo o legado: sem equivalente Firestore (o código já era capacidade nova); esta
change é UX pura sobre ela.

## What Changes

- **Ponto de entrada no menu da conta** (o card de usuário no rodapé da sidebar,
  `AppShell.tsx`): novo item "Entrar em outro workspace com código", posicionado junto às
  ações de participação (após "Equipe e convites", antes de "Alternar tema"). É o único
  menu **sempre presente** — reachável inclusive por quem tem **exatamente um** workspace
  (o caso do dono do demo). O seletor de workspace NÃO serve como porta primária: ele só
  renderiza com **mais de um** workspace (`workspace-context-switching`), justamente o que
  o primeiro-a-entrar ainda não tem.
- **Diálogo de entrada por código** (modal, reusando `ui/Modal`): um único campo editável
  — o **Código** (máscara `XXXX-XXXX` via `lib/auth/code.ts`, normalização tolerante) — e
  o e-mail da sessão exibido como contexto **somente-leitura** ("Entrando como
  `<email>`"). O usuário logado só digita o código; o e-mail é necessariamente o da conta
  (a invariante 6 §4.1 exige e-mail do convite idêntico ao autenticado).
- **Aceite reusa `consumeInviteByCode`**: no submit, chama
  `consumeInviteByCode(codigoNormalizado, emailDaSessao)`; no sucesso o próprio
  `consumeInviteByCode` já troca para o novo workspace (`selectWorkspace`) — o diálogo
  fecha e navega para `/` (Visão Geral). Zero duplicação da lógica de aceite ou de erro.
- **Estados de erro** reusando o mapa existente: par inválido/não encontrado (genérico),
  `invitation_code_locked` (código travado), `invitation_code_expired`/expirado (link
  ainda pode valer), já usado, já é membro, e o **e-mail divergente** (o convite foi
  emitido para outro e-mail — orientação específica: sair e entrar com a conta certa, ou
  pedir um convite para o seu e-mail). Offline: a orientação "conecte-se para aceitar" já
  vem do `consumeInviteByCode`.
- **Abertura por query param** `?codigo=1` (espelhando o `?convidar=1` já usado na topbar),
  para que o diálogo seja endereçável e o item do menu apenas navegue com o param.
- **i18n**: rótulo do item de menu e textos do diálogo em `lib/i18n/invitations.ts` (a
  regra de CI exige que todo literal de convite viva ali).
- **Testes**: unidade (vitest/RTL) do diálogo e da fiação de menu; E2E do usuário logado
  entrando por código de ponta a ponta.

### Não-objetivos

- **Não cria rota nova de backend.** O `POST /api/v1/invitations/code/accept` já é
  autenticado e já atende este fluxo. Confirmado: **zero mudança de backend, zero
  migration** (verificação registrada no design D6). Se algo exigisse backend, esta change
  estaria mal escopada.
- **Não afrouxa a segurança.** Segue exigindo e-mail do convite **idêntico ao autenticado**
  (invariante 6 §4.1, condição 5); papel vem do servidor; o corpo não aceita `role`. Um
  usuário logado só aceita convites emitidos para o **próprio** e-mail — e isso é correto
  (ver questão em aberto Q1 no design).
- **Não permite digitar um e-mail diferente do da sessão** no diálogo in-app: como o
  aceite sempre usaria o e-mail autenticado, um campo de e-mail editável só produziria
  falha garantida e confusão. Quem tem um código para OUTRO e-mail usa o caminho da tela
  de login (deslogar e entrar com a conta correta).
- **Não cria "código de workspace" reutilizável** (join code aberto): já descartado em
  `invite-by-code` §Não-objetivos — outra entidade, outro modelo de ameaça.
- **Não altera a matriz de autorização** nem o fluxo do link (`/convite/:token`) nem a
  seção de código da tela de login (esta última é o caminho para não-autenticados e
  permanece; sua melhoria é a questão em aberto Q3, fora de escopo por ora).
- **Não trata aceite por código offline** (mesma razão do `invite-by-code`): aceitar exige
  rede; o diálogo diz "conecte-se para aceitar".

### Impact

- **Frontend** (o grosso): `AppShell.tsx` (item no menu da conta + fiação `?codigo=1`);
  novo componente de diálogo (sob `features/auth/` ou `features/invitations/`, reusando
  `consumeInviteByCode`, `lib/auth/code.ts`, `ui/Modal`); novos literais em
  `lib/i18n/invitations.ts`. Nenhuma tela nova obrigatória (o diálogo é o suficiente); um
  alias de rota autenticada é opcional.
- **Backend**: **nenhum**. Consumido, não modificado.
- **Dependências** (consumidas, não modificadas): `invite-by-code`
  (`consumeInviteByCode`, `invitationsApi.acceptByCode`, `lib/auth/code.ts`, mapa de erro,
  literais `code*`), `app-shell-navigation` (menu da conta em `PortalMenu`, padrão
  `?param=1`), `workspace-context-switching` (`switchWorkspace`/`selectWorkspace`,
  invalidação anti-vazamento na troca).
- **Divergência registrada** (não silenciosa): a spec `app-shell-navigation` afirma que o
  menu da conta tem "exatamente três itens"; a realidade já tem **quatro** (o menu foi
  consolidado no card de usuário). Esta change acrescenta um **quinto**. A divergência é
  reconciliada no `EXECUCAO.md` (decisão DE-G0.1), seguindo a regra da casa de registrar,
  não esconder. Mantemos o delta de spec como `ADDED` na capacidade nova (padrão do repo:
  todos os 26 deltas anteriores são `ADDED`), sem `MODIFIED` sobre `app-shell-navigation`.
- **BREAKING**: nenhum. Tudo aditivo.

## Capabilities

### New Capabilities

- `join-workspace-by-code`: ponto de entrada descobrível e SEMPRE acessível (menu da conta)
  para um usuário autenticado entrar noutro workspace por código; diálogo com o e-mail da
  sessão fixo (somente-leitura) e um único campo de código; aceite reusando
  `consumeInviteByCode` (troca de workspace + navegação para a Visão Geral no sucesso);
  estados de erro reusando o mapa existente (par inválido, travado, expirado, já usado, já
  membro, e-mail divergente, offline); acessibilidade (fundo temático regra F, alvo de
  toque ≥ 32px, foco preso, `aria-live`, nome acessível único regra G). Sem rota de
  backend nova; a invariante de e-mail idêntico ao autenticado permanece intacta.

### Modified Capabilities

Nenhuma via delta de spec. A observação sobre o menu da conta de `app-shell-navigation`
(3 → 5 itens) é registrada como divergência no `EXECUCAO.md`, coerente com a consolidação
já ocorrida.
