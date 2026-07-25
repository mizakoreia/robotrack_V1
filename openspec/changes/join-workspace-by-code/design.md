## Context

`invite-by-code` já entregou, ponta a ponta, o aceite de convite por **código** para um
usuário autenticado. A maquinaria de frontend reusada aqui, verificada no código real:

| Peça (caminho real) | Papel | Como esta change reusa |
|---|---|---|
| `lib/auth/session.ts` — `consumeInviteByCode(code, email)` | Limpa o par, checa offline, chama `acceptByCode`, no sucesso `selectWorkspace(workspace_id)` + toast, mapa de erros compartilhado | **Chamado como está.** É o motor do aceite in-app |
| `lib/api/endpoints.ts` — `invitationsApi.acceptByCode({code,email})` → `POST /api/v1/invitations/code/accept` (autenticado) | Aceite atômico no servidor (invariante 6) | Consumido, não tocado |
| `lib/auth/code.ts` — `normalizeInviteCode`, `formatInviteCode`, `isCompleteInviteCode`, `CODE_LENGTH=8` | Máscara `XXXX-XXXX` + normalização tolerante | Reusado no campo do diálogo |
| `features/auth/AuthPage.tsx` — `onSubmitCode`, ramo `if (isAuthenticated) await consumeInviteByCode(...)` | O MESMO fluxo, na tela de login | O diálogo espelha só o ramo autenticado |
| `lib/i18n/invitations.ts` — literais `code*` (regra de CI: literal de convite só aqui) | Textos | Ganha o rótulo do menu + textos do diálogo |
| `app/AppShell.tsx` — menu da conta em `PortalMenu` (4 itens), padrão `?convidar=1` na topbar | Superfície de navegação | Ganha o item + a fiação `?codigo=1` |
| `lib/workspace/switchWorkspace.ts` / `store/workspaceStore.ts` — `switchWorkspace`/`selectWorkspace` | Troca de workspace com descarte total do cache (anti-vazamento) | Acionado indiretamente por `consumeInviteByCode` |
| `components/ui/Modal.tsx` — foco preso, `Esc` devolve ao gatilho | Primitivo de modal | Base do diálogo |

O trabalho de design **não é** "como aceitar por código" (isso está pronto e imutável). É
**onde a porta fica** e **como o diálogo se comporta** para o usuário logado, sem afrouxar
nenhuma invariante e sem duplicar lógica.

Decisões de produto herdadas e não reabertas: código é por-convite/por-e-mail; coexiste
com o link; só o dono convida; e-mail idêntico ao autenticado é a proteção central.

## Decisões

### D1 — Porta primária: o menu da conta (card de usuário), não o seletor de workspace

**Decisão.** O ponto de entrada primário é um item "Entrar em outro workspace com código"
no **menu da conta** (o card de usuário no rodapé da sidebar, `AppShell.tsx`), entre
"Equipe e convites" e "Alternar tema".

**Por quê.** O caso que motiva a change é o dono do demo: um usuário com **exatamente um**
workspace (o próprio) que quer entrar noutro. O seletor de workspace
(`WorkspaceContext.tsx`) **só renderiza como controle quando há mais de um workspace**
(requisito de `workspace-context-switching`: "Seletor de workspace só existe com mais de
um workspace") — logo ele é invisível justamente para quem mais precisa da porta. O menu
da conta é o único **sempre presente** na área autenticada, independente do número de
workspaces. Colocar a ação de participação junto de "Equipe e convites" também é coerente
tematicamente (ambas são ações de composição de time).

**Onde a invariante mora.** Na UI (posição do item) — sem efeito de autorização; a
autoridade continua no servidor.

**Alternativa descartada.** Porta no **seletor de workspace**. Rejeitada como primária: não
existe com 1 workspace (o caso alvo). Fica como aprimoramento secundário opcional (ver Q2)
— aditivo, para quem já tem >1 e pensa no seletor como "onde troco de workspace".

**Alternativa descartada.** Um controle dedicado na **topbar** (ícone/botão próprio ao lado
do contexto de workspace). Rejeitada: adiciona peso permanente à topbar contra a restrição
de produto "cada pixel serve a uma tarefa"; a ação é ocasional (não diária), então mora
melhor num menu do que sempre à vista.

### D2 — Diálogo com e-mail da sessão fixo (somente-leitura) e só o código editável

**Decisão.** O diálogo mostra "Entrando como `<email da sessão>`" como texto de contexto
**somente-leitura** e oferece **um único** campo editável: o Código (máscara `XXXX-XXXX`,
normalização tolerante). No submit, chama `consumeInviteByCode(codigo, emailDaSessao)`.

**Por quê.** O aceite exige, pela invariante 6 (§4.1, condição 5), que o e-mail do convite
seja idêntico ao e-mail **autenticado**. Para um usuário logado, esse e-mail é
necessariamente o da sessão — não há grau de liberdade. Um campo de e-mail editável só
poderia (a) repetir o e-mail da sessão (redundante) ou (b) divergir dele, produzindo falha
garantida. Fixar o e-mail e pedir só o código honra o princípio "estado honesto"
(PRODUCT.md §2): a UI não oferece um controle que não pode dar certo. Também reduz o
diálogo a **um campo** — ideal para o uso de luva (menos digitação, alvo grande).

**Onde a invariante mora.** No servidor (a comparação de e-mail no `consume`, inalterada) +
na UI (o e-mail passado é o da sessão, nunca digitado).

**Alternativa descartada.** Repetir a UI da tela de login (campos E-mail **e** Código).
Rejeitada: na tela de login o e-mail é necessário porque o usuário ainda não está
autenticado; logado, ele é conhecido e imutável — pedir de novo é ruído e abre a porta ao
modo de falha "digitei outro e-mail e não entendi por que falhou".

### D3 — O aceite REUSA `consumeInviteByCode`; o diálogo não fala com a API

**Decisão.** O diálogo não chama `acceptByCode` nem monta mapa de erro próprio: ele chama
`consumeInviteByCode`, que já faz limpeza do par, guarda offline, chamada, troca de
workspace (`selectWorkspace`) e toast, e já traduz todos os códigos de erro. O diálogo só
cuida de: coletar o código, exibir estado de carregando, renderizar a mensagem de erro que
`consumeInviteByCode` devolve, e no sucesso fechar + `navigate('/')`.

**Por quê.** É a regra da casa (reusar o consumo, nunca duplicar a lógica delicada). O ramo
autenticado do `AuthPage.onSubmitCode` já prova que essa é a superfície certa. Duplicar
levaria as duas cópias a divergirem na primeira correção de erro.

**Onde a invariante mora.** No `consumeInviteByCode`/`consume` já existentes.

**Alternativa descartada.** Um hook novo `useJoinByCode` que chamasse `acceptByCode`
diretamente. Rejeitada: reimplementaria o mapa de erro, o `selectWorkspace` e a checagem de
offline que já vivem no `consumeInviteByCode`.

### D4 — Abertura por query param `?codigo=1`, espelhando `?convidar=1`

**Decisão.** O item de menu navega para a rota atual com `?codigo=1`; o `AppShell` observa
o param e abre o diálogo (fechá-lo remove o param). Espelha o padrão já usado pela topbar
para "Convidar pessoa" (`?convidar=1`).

**Por quê.** Endereçável (dá para linkar/abrir direto), consistente com o padrão existente,
e não exige um arquivo de rota nem uma tela nova. Como o usuário já está autenticado, não
há redirect de OAuth a sobreviver — logo **não** é preciso `sessionStorage` (diferente do
fluxo da tela de login, que precisa do `inviteStore` por causa do OAuth).

**Onde a invariante mora.** Na UI (leitura do param no `AppShell`).

**Alternativa descartada.** Uma rota-página `/entrar-com-codigo` dentro do bloco
`ProtectedRoute`. Não rejeitada em princípio — fica como **opcional** (um alias que abre o
mesmo diálogo), se o dono preferir um destino linkável fora de contexto. O diálogo via
param é o suficiente e mais leve.

### D5 — Estados de erro: reusar o mapa, com a leitura correta do e-mail divergente

**Decisão.** Todas as mensagens vêm do mapa de `consumeInviteByCode`: par
inválido/não-encontrado (genérico), `invitation_code_locked` (travado), expirado (link
pode valer), já usado, já é membro, **e-mail divergente**, offline. Para o usuário logado,
o "e-mail divergente" tem leitura específica e importante: **o convite foi emitido para
outro e-mail** — a orientação é "saia e entre com a conta correta, ou peça um convite para
o seu e-mail", nunca o genérico "não foi possível aceitar".

**Por quê.** Sem essa leitura, o usuário logado que tenta um código destinado a outro
e-mail veria uma mensagem opaca. Nomear o modo de falha concreto é regra da casa
(config.yaml: "aceite nomeia o modo de falha concreto").

**Onde a invariante mora.** No mapa de erro já existente (`session.ts`) + nos literais de
`invitations.ts` (reusar `codeInvalidPair`/`codeLocked`/`codeExpired`; se faltar um literal
para o caso "convite para outro e-mail estando logado", acrescentar em `invitations.ts`).

**Alternativa descartada.** Um mapa de erro específico do diálogo. Rejeitada por D3.

### D6 — Confirmação: nenhuma rota de backend nova, nenhuma migration

**Decisão / verificação.** `POST /api/v1/invitations/code/accept` já é declarado
autenticado e tenant-exempt em `invite-by-code` (G2.4), com `route_setting :policy,
access: :authenticated`. O aceite por um usuário logado é **exatamente** o que ele já faz.
Portanto esta change **não** adiciona rota, endpoint, coluna, índice, policy, entrada de
allowlist, throttle nem migration. As varreduras (route-sweep, cross-tenant, tenant-sweep)
**não mudam**.

**Por quê registrar.** O prompt pede confirmar que "nenhuma rota nova de backend deveria
ser necessária". Confirmado. Qualquer necessidade de backend seria sinal de escopo errado.

**Onde a invariante mora.** Já no backend do `invite-by-code` (inalterado).

### D7 — Acessibilidade e alvo de toque (DESIGN.md / PRODUCT.md)

**Decisão.** O campo de código usa **fundo temático** (regra F do `convention-sweep`: campo
nativo sem fundo temático reprova — senão fica branco-sobre-branco no escuro). Alvo de toque
≥ 32px (PRODUCT.md: ≥ 32px por luva; o `invite-by-code` usou 37–39px, seguimos a mesma
faixa). O diálogo usa `ui/Modal` (foco preso em ciclo, `Esc` devolve ao gatilho). Erro
anunciado por `aria-live`. O nome acessível do item de menu e do botão de submit não colide
com nenhum outro controle da mesma tela (**regra G**: nome de botão do shell não é reusado)
— "Entrar em outro workspace com código" é distinto de "Convidar pessoa"/"Equipe e
convites". Tema NÃO segue o SO (herdado). Nenhum token/primitivo/motion/ban novo — por isso
`DESIGN.md` **não** é alterado (reuso puro).

**Onde a invariante mora.** Nos tokens de campo já medidos no CI (`tests/contrast.test.ts`)
+ nas regras F/G do `convention-sweep` (que a suíte já roda) + no `ui/Modal`.

**Alternativa descartada.** Um input estilizado ad-hoc. Rejeitada: reprovaria a regra F e o
contraste medido; reusar os tokens de campo é obrigatório.

## Questões em aberto (para o dono) — cada uma com recomendação

### Q1 — O e-mail do convite pode ser diferente do e-mail logado?

**Situação.** O aceite exige e-mail do convite **idêntico ao autenticado** (invariante 6,
condição 5). Logo, um usuário logado só consegue aceitar convites emitidos para o **próprio**
e-mail. Se o convite foi para outro e-mail, ele **não** pode aceitar enquanto logado como si
mesmo — precisaria entrar com a conta daquele e-mail (caminho da tela de login).

**Implicação.** Isto é **correto por segurança** e não deve ser afrouxado: o vínculo
código↔e-mail é o que impede que adivinhar um código curto (2⁴⁰) vire acesso. Afrouxar
transformaria o código numa credencial suficiente sozinha.

**Recomendação.** Manter a invariante. No diálogo in-app, **não** oferecer campo de e-mail:
usar o da sessão e, no caso de convite destinado a outro e-mail, mostrar a orientação
específica (sair e entrar com a conta certa, ou pedir convite para o e-mail atual).
Documentar isto na ajuda do diálogo. **Nada muda no backend.**

### Q2 — Ponto de entrada exato na UI

**Recomendação (primária).** Item "Entrar em outro workspace com código" no **menu da
conta** (card de usuário, `AppShell.tsx`), entre "Equipe e convites" e "Alternar tema" —
sempre acessível, inclusive com 1 workspace (D1).

**Secundário (opcional, aditivo).** Um item "Entrar com código…" ao fim do menu do
**seletor de workspace** (`WorkspaceContext.tsx`), visível só quando há >1 workspace — para
quem pensa no seletor como "onde gerencio meus workspaces". Recomendo **deferir** este
secundário para manter a change mínima; incluir só se o dono quiser reforço de descoberta.

### Q3 — Melhorar também a descoberta na tela de login?

**Situação.** A seção de código na tela de login é hoje um `<details>` recolhido ("Tenho um
código de convite").

**Recomendação.** **Fora de escopo** desta change (que fecha o buraco do usuário
**logado**). A tela de login serve o não-autenticado e já tem a seção. Se o dono quiser, um
follow-up pequeno pode deixá-la mais visível (ex.: expandida por padrão quando há um par em
`sessionStorage`). Recomendo tratar como item separado, não misturar aqui.

## Riscos / trade-offs

- **Descoberta depende de o usuário abrir o menu da conta.** Mitigação: rótulo explícito e
  próximo de "Equipe e convites"; o secundário do seletor (Q2) reforça se o dono aprovar.
- **Divergência da spec `app-shell-navigation`** ("menu da conta com exatamente três
  itens"): a realidade já tem quatro (consolidação prévia); esta change vai a cinco.
  Registrada no `EXECUCAO.md` (DE-G0.1); a verificação do G1 confere se algum teste asserta
  contagem exata e o reconcilia. Sem `MODIFIED` de spec (padrão do repo é `ADDED`-only).
- **Nenhum risco de segurança novo:** reuso puro do aceite autenticado; nada afrouxa (D6).
