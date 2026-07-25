# EXECUCAO — robot-task-grouping

Mapa de execução. Escrito ANTES do código (commit G0). RETOMADA no fim.

## Ponto de partida

- Branch: `main` @ `0f84014` (= origin/main, com toda a `impeccable-remediation`).
- Marcador de segurança: `git tag pre-task-grouping` @ `0f84014` (voltar:
  `git reset --hard pre-task-grouping`).
- **NÃO** comitar `frontend/vite.config.ts` nem `frontend/src/lib/api/client.ts` (túnel).
- **NÃO** reiniciar servidores de dev (:5173/:3000)/túneis; o Vite recarrega sozinho.

## Reconciliação (mapeado no código, G0)

- Categoria = `tasks.cat` texto livre (1–120), semeada de 9 categorias de template; servidor
  ordena por `position` (sem `ORDER BY cat`). Agrupamento hoje é run-length visual em
  `RobotTaskTablePage.tsx:149-197`.
- Progresso: views SQL no servidor (ponderado ignora N/A; crua conta N/A no total); rollup por
  `Progress::CascadeRecompute`. Cliente só consome.
- Exclusão INDIVIDUAL já existe: soft-delete owner-only (`Tasks::DeleteService`), views filtram
  `deleted_at IS NULL`, avanços preservados (FK RESTRICT + trilha imutável). **"apagar sem
  quebrar cálculo" já está resolvido** — o novo é só o LOTE.

## Ordem dos grupos

| Grupo | Escopo | Camada |
|---|---|---|
| **G1** | Categorias colapsáveis (grupos reais, prefixo A./B., contagem, estado por robô) | frontend |
| **G2** | `Tasks::BulkDeleteService` + `DELETE /tasks` (owner-only, 1 recálculo/robô) | backend |
| **G3** | Seleção múltipla + barra + confirmação → bulkRemove | frontend |
| **G4** | Suíte + validate --strict + docs + ff/push | ambos |

## Decisões fixadas (design.md — não reabrir)

- **D-TG-1** grupos reais por `cat`, ordem por 1ª aparição (corrige título repetido).
- **D-TG-2** prefixo A./B. visual, por índice do grupo.
- **D-TG-3** cabeçalho mostra contagem, nunca % de categoria (não recalcular no cliente).
- **D-TG-4** default tudo aberto; persiste só as recolhidas, por robô, em safeStorage.
- **D-TG-5** colapsar remove `<tr>`/cartões do DOM; `<button aria-expanded>`; a11y.
- **D-TG-6** lote: 1 transação, `update_all(deleted_at:)` (sem callbacks) + `CascadeRecompute`
  1×/robô; SEM `without_cascade`; ids invisíveis ignorados pela RLS.
- **D-TG-7** owner-only no nível de coleção (`TaskPolicy#destroy?`).

## RETOMADA

*(preenchido ao fim de cada grupo)*
