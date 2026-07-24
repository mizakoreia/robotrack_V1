# CLAUDE.md — regras de trabalho neste repositório

Leia também, em ordem: **`CONTINUIDADE.md`** (estado, método, o que resta),
**`VALIDACAO_WSL.md`** (handoffs que só a WSL/deploy fecham), **`PRODUCT.md`** e
**`DESIGN.md`** (contexto de produto e sistema visual — o skill `impeccable` os lê
antes de qualquer comando).

## Documentação ANTES de cada push

**Atualizar a documentação é parte do push, não um passo posterior.** Antes de
`git push`, verifique se a mudança altera algo que os documentos afirmam — e
atualize no MESMO push (ou num commit imediatamente anterior, no mesmo empurrão):

| Mudou | Atualize |
|---|---|
| Estado, suítes, tip da `main`, o que resta | `CONTINUIDADE.md` |
| Procedimento de validação, comando, seletor de teste, topologia de ambiente | `VALIDACAO_WSL.md` |
| Decisão de execução, reconciliação, handoff, resultado de grupo | `openspec/changes/<change>/EXECUCAO.md` + `tasks.md` |
| Sistema visual (token, primitivo, motion, ban) | `DESIGN.md` |
| Usuários, propósito, princípios, anti-referências | `PRODUCT.md` |

Regra de ouro: **um documento que afirma algo falso é pior que ausente.** Se um
runbook manda clicar num botão que não existe mais, ele custa uma rodada do par.
Ao remover/renomear um controle, procure-o nos `.md` (`grep -rn "<rótulo>" *.md`).

Nada de `[x]` em `tasks.md` sem prova verde. Handoff é anotado como handoff.

## Método por grupo

1. Uma change por vez, na branch de feature, **ff para `main` a cada grupo**.
2. **Antes de qualquer código**, `EXECUCAO.md` reconciliando design × realidade
   (commit `G0`).
3. Por grupo: aplicar → specs dirigidos 0 falhas → marcar `tasks.md` →
   `npx --yes @fission-ai/openspec@1.6.0 validate <change> --strict` → **atualizar
   docs** → UM commit → ff `main` + push.
4. Divergência entre design e realidade: decidir, **registrar o motivo** no
   `EXECUCAO.md`. Nunca em silêncio.
5. Resumo pt-BR client-friendly ao fim de cada grupo (cliente não-expert).

## Commits

Rodapé `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`. **Nunca** inclua
o id do modelo em artefato versionado. Assinatura de commit é impossível neste
ambiente (sem chave) — "Unverified" é esperado.

Mensagem de commit via `git commit -F -` com heredoc `<<'EOF'`: crase em mensagem
inline é substituição de shell e come o texto.

## Convenções que não regridem

- Frontend: hooks em `features/<dominio>/` com a factory `qk.*`; telas em `app/`
  não importam `lib/api`; invalidar a chave específica; `createPortal` só em
  `components/menu/` (+ `ui/Modal`); `new Notification(` só no hook de alerta;
  storage só por `lib/safeStorage`. Os sweeps em `frontend/tests/` travam isso.
- Campo nativo (`input`/`select`/`textarea`) precisa de **fundo temático** — sem
  ele fica branco-sobre-branco no escuro (regra F do `convention-sweep`).
- Nome de botão do `AppShell` não é reusado em outra tela: dois controles de mesmo
  nome acessível na mesma tela é defeito (regra G).
- Banco: a app conecta como `robotrack_app` **sem SUPERUSER e sem BYPASSRLS**;
  isolamento é **RLS forçada**; invariantes moram no banco (trigger/CHECK/índice);
  vazamento cross-tenant responde **404**, nunca 403.
- E2E: **ancore locators por região/diálogo** e use `{ exact: true }`. Quatro
  rodadas foram perdidas com `getByLabel`/`getByText` casando por substring numa
  tela que ganha elementos conforme o fluxo avança.
- O repositório legado `mizakoreia/RoboTrack` é **somente leitura de referência**.
