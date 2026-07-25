# EXECUCAO — join-workspace-by-code

Registro de execução por grupo: reconciliação com a realidade do repo, decisões tomadas,
armadilhas e provas. Método da casa (CLAUDE.md): uma change por vez, grupo a grupo, specs
dirigidos 0 falhas, doc atualizada no mesmo passo, um commit `G<n>:` por grupo.

> **Estado desta change:** PLANEJAMENTO/FORMALIZAÇÃO OpenSpec. G0 (esta reconciliação +
> esqueleto) concluído nesta sessão; G1 e G2 são código/testes ainda NÃO executados.
>
> **Restrição de git vigente (instrução do dono):** NÃO fazer push para `origin` e NÃO
> fazer `git merge --ff-only main`. O trabalho vive na branch local `feat/invite-by-code`
> (a change nova é aditiva — só arquivos em `openspec/`); commit `G0:` de planejamento é
> LOCAL. Qualquer necessidade de subir é PERGUNTA, não ação.

---

## G0 — Reconciliação (este documento) + esqueleto OpenSpec

### O problema, em uma frase

Um usuário AUTENTICADO (ex.: o dono do demo) não tem, dentro do app, onde aplicar um
código de convite: o único campo de código vive na tela de entrada (`/entrar`), por onde
ele não passa estando logado. Ele só chegaria lá deslogando.

### O que já existe e será REUSADO (levantado no código real, não só no plano)

A change `invite-by-code` já entregou o aceite por código ponta a ponta. Esta change
CONSOME, sem modificar:

| Peça (caminho real) | Papel | Como esta change reusa |
|---|---|---|
| `lib/auth/session.ts` — `consumeInviteByCode(code, email)` (linha ~116) | Limpa o par, checa offline, chama `acceptByCode`, no sucesso `selectWorkspace(workspace_id)` + toast, mapa de erros compartilhado | **Chamado como está** pelo diálogo. É o motor |
| `lib/api/endpoints.ts` — `invitationsApi.acceptByCode({code,email})` → `POST /api/v1/invitations/code/accept` (autenticado) | Aceite atômico no servidor | Consumido, não tocado |
| `lib/auth/code.ts` — `normalizeInviteCode`, `formatInviteCode`, `isCompleteInviteCode`, `CODE_LENGTH=8` | Máscara `XXXX-XXXX` + normalização tolerante | Reusado no campo do diálogo |
| `features/auth/AuthPage.tsx` — `onSubmitCode`, ramo `if (isAuthenticated) await consumeInviteByCode(...)` (linha ~62) | O MESMO fluxo, na tela de login | O diálogo espelha só o ramo autenticado |
| `lib/i18n/invitations.ts` — literais `code*` (regra de CI: literal de convite só aqui) | Textos | Ganha rótulo de menu + textos do diálogo |
| `app/AppShell.tsx` — menu da conta (card de usuário) em `PortalMenu`; topbar com padrão `?convidar=1` | Superfície de navegação | Ganha o item + a fiação `?codigo=1` |
| `lib/workspace/switchWorkspace.ts` / `store/workspaceStore.ts` — `switchWorkspace`/`selectWorkspace` | Troca de workspace com descarte total do cache (anti-vazamento) | Acionado indiretamente por `consumeInviteByCode` |
| `components/ui/Modal.tsx` — foco preso, `Esc` devolve ao gatilho | Primitivo de modal | Base do diálogo |
| `POST /api/v1/invitations/code/accept` (backend, `invite-by-code` G2.4, `access: :authenticated`) | Aceite autenticado por código | **Já atende este fluxo.** Nada muda no backend |

### Divergências entre o design idealizado e a realidade (reconciliadas)

**DE-G0.1 — Menu da conta: a spec `app-shell-navigation` está desatualizada.** A spec diz
"Menu da conta tem três itens" (Adicionar usuário / Alternar tema / Sair). A REALIDADE
(`AppShell.tsx`, card de usuário) já tem **quatro** — 'Configurações do workspace', 'Equipe
e convites', 'Alternar tema', 'Sair' — por causa da consolidação da conta no card de
usuário (registrada na "Rodada de UI/UX" do `CONTINUIDADE.md`). Esta change acrescenta um
**quinto** item. **Decisão:** manter o delta de spec desta change como `ADDED` na
capacidade nova (padrão do repo: todos os 26 deltas anteriores são `ADDED`; não há store de
specs-base nem exemplo de `MODIFIED`, e `validate --strict` é comprovadamente verde nesse
padrão). A divergência com a spec antiga fica registrada AQUI. **Armadilha para o G1:**
conferir se algum teste do shell (`AppShell`/`Sidebar`) asserta contagem EXATA de itens do
menu da conta; se sim, atualizá-lo no mesmo grupo (a contagem real já é 4, não 3 — o teste,
se existir, já foi ajustado na consolidação; confirmar).

**DE-G0.2 — Seletor de workspace NÃO pode ser a porta primária.** `workspace-context-
switching` exige que o seletor só exista com >1 workspace. O caso alvo (dono do demo) tem
1. **Decisão:** porta primária no menu da conta (sempre presente); o seletor é aprimoramento
secundário opcional (Q2), deferido.

**DE-G0.3 — E-mail não é grau de liberdade para o usuário logado.** A invariante 6 exige
e-mail do convite == e-mail autenticado. **Decisão (D2 do design):** o diálogo in-app não
oferece campo de e-mail; usa o da sessão e mostra "Entrando como `<email>`" somente-leitura.
Diferente da tela de login (onde o e-mail é digitado porque ainda não há sessão).

**DE-G0.4 — Sem `sessionStorage`/OAuth no fluxo in-app.** O `inviteStore` (captura do par
para sobreviver ao redirect do Google) é necessário na tela de login; aqui o usuário já
está autenticado, sem redirect a sobreviver. **Decisão:** abrir por query param `?codigo=1`
(D4), sem `sessionStorage`.

**DE-G0.5 — Sem rota de backend nova (confirmação pedida pelo dono).** Verificado: o
endpoint autenticado já existe e já atende. **Decisão/registro (D6):** zero backend, zero
migration, varreduras inalteradas. Se o G1 revelasse necessidade de backend, o escopo
estaria errado.

### Decisões-âncora (detalhadas em design.md D1..D7)

- **D1** porta primária no menu da conta (sempre acessível, inclusive com 1 workspace); não
  o seletor (só existe com >1).
- **D2** diálogo com e-mail da sessão fixo (somente-leitura); só o código é editável.
- **D3** aceite reusa `consumeInviteByCode`; o diálogo não fala com a API nem monta mapa de
  erro próprio.
- **D4** abertura por `?codigo=1` (espelha `?convidar=1`); rota-página é opcional.
- **D5** estados de erro reusam o mapa; e-mail divergente ganha leitura específica (convite
  para outro e-mail estando logado).
- **D6** nenhuma superfície de backend nova (confirmado).
- **D7** a11y: fundo temático (regra F), alvo ≥ 32px, foco preso, `aria-live`, nome
  acessível único (regra G); nenhum token/primitivo/motion/ban novo (DESIGN.md não muda).

### Mapa de grupos

- **G0** (este doc + esqueleto OpenSpec) — reconciliação, `validate --strict`. **[feito]**
- **G1** — frontend: diálogo + item no menu da conta + `?codigo=1` + i18n + vitest/RTL.
- **G2** — E2E (Chromium aqui; WebKit/CI handoff) + docs (`CONTINUIDADE`/`VALIDACAO_WSL`) +
  fechamento (commit `G<n>:` LOCAL, sem push).

### Questões em aberto para o dono (recomendação em design.md)

- **Q1** e-mail do convite ≠ e-mail logado → manter a invariante; usar o e-mail da sessão;
  orientação específica quando o convite for para outro e-mail. (Correto por segurança.)
- **Q2** ponto de entrada exato → **recomendo o menu da conta** (primário); seletor de
  workspace como secundário opcional, deferido.
- **Q3** melhorar a descoberta na tela de login → fora de escopo; follow-up separado.

### Prova do G0

- `npx --yes @fission-ai/openspec@1.6.0 validate join-workspace-by-code --strict` — verde.

---

## G1 — Frontend: diálogo + porta no menu da conta + i18n

### O que foi aplicado

- **`features/auth/JoinByCodeDialog.tsx`** (novo): diálogo sobre `ui/Modal` (foco preso,
  `Esc` devolve o foco). E-mail da sessão (`useAuthStore`) exibido como contexto
  somente-leitura ("Entrando como `<email>`"); **um único** campo editável, o Código, com
  `formatInviteCode`/`normalizeInviteCode` de `lib/auth/code.ts` (máscara `XXXX-XXXX`,
  tolerante). Submit: valida `isCompleteInviteCode` (erro inline por `aria-live`), chama
  `consumeInviteByCode(código, emailDaSessão)`, e **só no sucesso** fecha + `navigate('/')`.
  Campo com `bg-bg-main`/`border-input`/`text-text-main` (regra F) e `py-2` (alvo ≥ 32px).
- **`app/AppShell.tsx`**: item "Entrar em outro workspace com código" no menu da conta
  (`inviteText.joinByCodeMenu`), entre "Equipe e convites" e "Alternar tema"; abertura por
  `?codigo=1` via `useSearchParams` (fechar remove o param); `<JoinByCodeDialog>` montado na
  casca persistente.
- **`lib/i18n/invitations.ts`**: `joinByCodeMenu`/`joinByCodeTitle`/`joinByCodeHint`/
  `joinByCodeAs`/`joinByCodeSubmit`.
- **`lib/auth/session.ts`**: `consumeInviteByCode` agora retorna `boolean` (DE-G1.1).

### Decisões do grupo

**DE-G1.1 — `consumeInviteByCode` retorna `boolean` (antes `void`).** O diálogo precisa
saber se ENTROU de fato para decidir fechar+navegar; em erro deve permanecer aberto com o
código digitado. **Decisão:** adicionar valor de retorno (`true` só no sucesso), sem mudar o
comportamento de toast (o feedback ao usuário continua no toast — canal único de convite da
casa). Backward-compatible: `AuthPage` e `handleInviteAfterAuth` ignoram o retorno (só
`await`). **Alternativa descartada:** um hook novo chamando `acceptByCode` direto —
reimplementaria o mapa de erro e o `selectWorkspace` (viola D3, a regra de reuso).

**DE-G1.2 — Item secundário no seletor de workspace (Q2) DEFERIDO.** Só apareceria com >1
workspace; a porta primária (menu da conta) já cobre o caso alvo. Mantida a change mínima,
conforme a recomendação Q2 adotada pelo dono. Reabrir é aditivo.

**DE-G0.1 (resolvida) — contagem de itens do menu da conta.** O teste
`app/__tests__/AppShell.test.tsx` NÃO assertava contagem exata (itera por rótulo com
`getByRole('menuitem', { name })`). Adicionar o 5º item não quebrou nada; o teste foi
atualizado para incluir o novo rótulo (doc/teste verdadeiros). A spec `app-shell-navigation`
("três itens") segue desatualizada desde a consolidação — divergência registrada, sem
`MODIFIED` de spec (padrão `ADDED`-only do repo).

**DE-G1.3 — "convite para outro e-mail" reusa `emailMismatch`.** Para o usuário logado, um
código de convite emitido para OUTRO e-mail cai no `invitation_email_mismatch`, que
`consumeInviteByCode` já traduz no toast `emailMismatch` (com ação "Sair e entrar com outra
conta"). Nenhum literal novo — é exatamente a orientação específica pedida pela spec.

### Prova do G1

- `vitest` dirigido **35/35**: `JoinByCodeDialog.test.tsx` (6 — e-mail somente-leitura/sem
  campo de e-mail, máscara, incompleto não chama aceite, sucesso→aceite+fecha+`/`,
  falha→fica aberto, `Esc` fecha), `AppShell.test.tsx` (11 — inclui "porta com 1 workspace"
  e "item abre o diálogo `?codigo=1`"), `AuthPageCode.test.tsx` (5, regressão),
  `session.test.ts` (13, regressão).
- Sweeps: convenção/contraste/motion/stacking/tokens/query **66/66**, i18n de convites
  **3/3** (nenhum literal fora de `invitations.ts`). `tsc --noEmit` e `eslint` limpos.
- `validate --strict` verde.
