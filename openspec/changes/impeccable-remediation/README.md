# impeccable-remediation

Formaliza a `CRITICA_IMPECCABLE.md` (69 achados: 14 críticos, 31 importantes, 24 de
polimento) como uma change OpenSpec e a ataca **grupo a grupo**, por dor do operador.

- **Proposta:** `proposal.md` — por que (dívida de cumprimento, não redesenho) e o quê.
- **Design:** `design.md` — decisões D-IR-1…7 (onde cada invariante de a11y mora).
- **Specs delta:** `accessibility-compliance` (G1), `ui-primitives` (G2),
  `commissioning-report` (G3), `workspace-invitations` (G4).
- **Tarefas:** `tasks.md` — mapa de 6 grupos (G1–G6) ordenado por impacto.
- **Execução:** `EXECUCAO.md` — ordem, decisões, reconciliação, RETOMADA.

Método: um grupo por vez, prova verde (contraste/tsc/lint/vitest), ff para `main`,
**aprovação do dono entre grupos**. Marcador de segurança: `git tag
pre-impeccable-remediation` (@ `c2532a8`).
