## G0. Reconciliação e esqueleto da change

- [ ] G0.1 Materializar a change no formato OpenSpec (`proposal.md`, `design.md`,
  `specs/owner-only-deletion/spec.md`, `tasks.md`), coerente com `authorization-policies`
  (matriz como dado, `BasePolicy`, 403 vs. 404) e com `hierarchy-soft-delete` (a exclusão
  é arquivamento; o gatilho intercepta a transição, não o `DELETE`)
- [ ] G0.2 Escrever `EXECUCAO.md` reconciliando o design com a REALIDADE do repositório:
  o que já existe e é reusado (matriz de 8 actions, `permits`, `SoftDeleteService`,
  `Tenant` com `app.current_user_id`, gatilhos `memberships_owner_is_not_member` e
  `workspaces_owner_immutable` como precedente, válvula `app.invitation_purge` como
  precedente), as afirmações que deixam de ser verdadeiras ("a matriz tem 8 linhas";
  `legacy_parity.yml` L42 `covered_by`), e o mapa de grupos G0..G4 com decisões
- [ ] G0.3 Verificação do grupo: `npx --yes @fission-ai/openspec@1.6.0 validate
  owner-only-deletion --strict` verde

## G1. Autorização: a nona linha da matriz e as quatro policies

- [ ] G1.1 `app/policies/permission_matrix.rb`: acrescentar
  `destroy_commissioning: %i[owner]` após `manage_commissioning`, com comentário nomeando
  a divergência da §4.1 L2 (D1/D8). Atualizar o comentário de cabeçalho do arquivo, que
  hoje afirma "Oito chaves, uma por linha da tabela"
- [ ] G1.2 Remapear `destroy?` para `destroy_commissioning` em `project_policy.rb`,
  `cell_policy.rb`, `robot_policy.rb` e `task_policy.rb`, atualizando o comentário de
  cabeçalho de cada uma (as quatro citam hoje "criar/editar/excluir … owner/edit").
  `create?`, `update?`, `reorder?` e `assign?` **não mudam**
- [ ] G1.3 Atualizar `spec/policies/permission_matrix_spec.rb`: a reafirmação literal passa
  a ter 9 linhas, com o comentário da nova nomeando a divergência e a change que a
  introduziu (a mudança em dois lugares é proposital — D8)
- [ ] G1.4 Atualizar `spec/authorization/matrix_conformance_spec.rb`: a grade `ESPERADO`
  vai de 24 para 27 células (`destroy_commissioning`: owner `true`, edit `false`,
  view `false`)
- [ ] G1.5 Atualizar `config/authorization/legacy_parity.yml`: a entrada `L42 — projects
  allow write` migra de `covered_by` para `divergence`, explicando que o `write` único do
  Firestore foi dividido e que a exclusão foi endurecida para o dono. Manter as 22 entradas
  (contagem inalterada — o `legacy_parity_spec` a exige)
- [ ] G1.6 Specs de request dirigidos: editor recebe **403** no `DELETE` de projeto,
  célula, robô e tarefa, com o recurso intacto depois; leitor recebe 403; dona recebe 204 e
  a subárvore arquivada; membro de OUTRO workspace recebe **404** (nunca 403). Cobre os
  cenários do requisito "Excluir nó da hierarquia é exclusivo do dono"
- [ ] G1.7 Specs de não-regressão do papel `edit`: criar célula e robô (201), renomear
  (200), reordenar (200), atribuir responsável (200), registrar avanço — todos continuam
  verdes para `edit`
- [ ] G1.8 Verificação do grupo G1: suítes dirigidas de policies, autorização e hierarquia
  com 0 falhas; `role_comparison_guard_spec`, `route_sweep_spec`, `cross_tenant_spec`,
  `legacy_parity_spec` e os 8 `invariants/*` verdes; RuboCop limpo

## G2. Banco: o gatilho de arquivamento exclusivo do dono

- [ ] G2.1 Migration **aditiva e reversível**: `CREATE FUNCTION
  hierarchy_archive_owner_only()` (ramo 1 — sem transição de arquivamento, retorna; ramo 2
  — válvula `app.hierarchy_archive_bypass = 'on'`, retorna; ramo 3 — compara
  `app.current_user_id` com `workspaces.owner_user_id` e `RAISE EXCEPTION` com o texto da
  regra) + quatro `CREATE TRIGGER ... BEFORE UPDATE ON` `projects`, `cells`, `robots`,
  `tasks`. `down` derruba os quatro gatilhos e a função. **Não é tarefa destrutiva** — não
  apaga dado, não altera coluna, não reescreve tabela; logo não exige backup prévio
- [ ] G2.2 Regenerar `db/structure.sql` e conferir que a função e os quatro gatilhos
  entraram, seguindo a forma dos precedentes `memberships_owner_is_not_member` e
  `workspaces_owner_immutable`
- [ ] G2.3 Ligar a válvula, explicitamente, nos caminhos de manutenção sem usuário HTTP
  identificados no design (D3): `db/seeds`, restauração de `workspace_backups` e o
  `Legacy::*` dormente. Cada ponto ganha comentário dizendo por que a válvula está ali
- [ ] G2.4 **Verificação do reset de fábrica** (afirmação do design D3 que precisa de
  prova, não de suposição): o reset roda como a dona, dentro da transação de tenant que já
  emitiu `SET LOCAL app.current_user_id`, e portanto passa pelo ramo 3 **sem** a válvula.
  Se a prova falhar, a decisão vira "reset também liga a válvula" e é registrada no
  `EXECUCAO.md` — nunca corrigida em silêncio
- [ ] G2.5 Specs de banco (no idioma de `spec/authorization/db_invariants_spec.rb`):
  `UPDATE` de arquivamento com identidade de editor levanta; `UPDATE` de `name` com a mesma
  identidade passa; sessão sem `app.current_user_id` e sem válvula levanta; válvula ligada
  passa e morre no fim da transação; dona passa; rearquivar o que já está arquivado não
  levanta
- [ ] G2.6 Verificação do grupo G2: migration sobe e desce limpa (`db:migrate` +
  `db:rollback` + `db:migrate`); specs de banco 0 falhas; suítes de hierarquia,
  `workspace-settings` (reset) e `hierarchy-soft-delete` sem regressão

## G3. Frontend: a interface deixa de oferecer o que não pode

- [ ] G3.1 Predicado de papel para exclusão junto do `canManage` já existente
  (`AppShell.tsx:249` lê `workspaceStore.currentRoleLabel`), seguindo o mesmo idioma e
  mantendo o comentário de que papel no cliente é **rótulo, não autoridade**
- [ ] G3.2 `app/pages/ProjectPage.tsx`: o `IconButton` "Excluir <célula>" só renderiza para
  o dono. **Ocultar, não desabilitar** (D5). Criar e renomear célula permanecem para `edit`
- [ ] G3.3 `features/robot-tasks/AcoesCell.tsx`: a ação "Excluir" só renderiza para o dono;
  editar descrição e registrar avanço permanecem para `edit`
- [ ] G3.4 Testes de unidade (vitest/RTL): com papel `edit` os dois controles ausentes; com
  `owner` presentes; com `view` ausentes; e nenhum controle desabilitado introduzido.
  Locators por região/diálogo com `{ exact: true }` (regra da casa)
- [ ] G3.5 Verificação do grupo G3: vitest dirigido 0 falhas; sweeps de convenção,
  contraste e i18n verdes; `tsc` e `lint` limpos

## G4. E2E, documentação e fechamento

- [ ] G4.1 E2E do editor: entra no workspace como `edit`, abre o projeto, **não** encontra
  o controle de excluir, e a chamada direta à API responde 403 — a prova de que a ocultação
  é conveniência e o servidor é a autoridade. Aprovado no `e2e:lint`; execução em navegador
  é **HANDOFF** (`VALIDACAO_WSL.md`), como todo E2E da casa
- [ ] G4.2 Documentação no MESMO empurrão: `CONTINUIDADE.md` (seção da change, marcando que
  é **BREAKING para o papel `edit`**), `VALIDACAO_WSL.md` (seção do handoff do E2E novo) e
  varredura `grep -rn "excluir\|Excluir" *.md` atrás de runbook que mande um editor apagar
  algo — um documento que afirma algo falso é pior que ausente
- [ ] G4.3 Conferir que `DESIGN.md` e `PRODUCT.md` não precisam de mudança (nenhum token,
  primitivo, motion ou ban novo; nenhuma mudança de propósito/usuário) — e registrar essa
  conferência no `EXECUCAO.md` em vez de deixá-la implícita
- [ ] G4.4 Verificação final: `validate --strict` verde; suíte de backend e frontend sem
  falha nova; nenhum `[x]` sem prova verde; UM commit `G<n>:`; ff para `main` + push
  conforme o protocolo vigente; resumo pt-BR client-friendly entregue
