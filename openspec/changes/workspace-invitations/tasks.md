## 1. Contrato com workspace-tenancy e esquema

- [x] 1.1 Verificar, contra o change `workspace-tenancy` já mergeado, que `people`
  tem coluna `email`, índice único `people (workspace_id, id)` e `user_id` nullable;
  se `people.email` não existir, abrir bloqueio antes de escrever qualquer código
  (D10 — sem `people.email` o aceite passa a criar sempre `Person` nova e duplica
  o responsável pré-cadastrado, quebrando "Minhas Tarefas" para quem já tinha
  tarefas atribuídas)
- [x] 1.2 Migration `create_invitations`: PK `uuid`, `workspace_id NOT NULL`, `token`,
  `email`, enum Postgres `invitation_role ('view','edit')`, `created_by_person_id`,
  `expires_at NOT NULL DEFAULT now() + interval '7 days'`, `used_at`,
  `used_by_user_id`; na mesma migration, as constraints: único em `token`,
  `CHECK (email = lower(email))`, `CHECK (char_length(email) <= 254)`,
  `chk_invitations_consumption` e FK composta
  `(workspace_id, created_by_person_id) → people (workspace_id, id)`
  (§4.1 inv. 7 — `INSERT` com `role = 'owner'` falha no enum e `UPDATE` gravando
  `used_at` sem `used_by_user_id` falha no CHECK, ambos sem passar por model)
- [x] 1.3 Migration aditiva `add_invitation_id_to_memberships` (nullable,
  `REFERENCES invitations(id) ON DELETE RESTRICT`) + índice único parcial
  `idx_memberships_one_per_invitation ... WHERE invitation_id IS NOT NULL`
  (§4.1 inv. 6 — dois `INSERT` de membership com o mesmo `invitation_id` colidem;
  memberships migradas com `invitation_id NULL` não colidem entre si)
- [x] 1.4 Habilitar RLS em `invitations` por `app.current_workspace_id` (D2) e criar
  a função `SECURITY DEFINER invitation_by_token(text)` para os dois caminhos
  sem workspace corrente (pré-visualização e aceite) (§4.1 inv. 1 — um `SELECT *
  FROM invitations` com `app.current_workspace_id = WS-A` não retorna nenhuma linha
  de `WS-B`, e a função só devolve por token exato, nunca listagem)
- [x] 1.5 Spec de banco que exercita 1.2–1.4 por SQL cru, sem passar por
  ActiveRecord: 6 inserções inválidas, cada uma esperando a violação nomeada
  (verificação do grupo 1 — prova que a invariante não mora só no model)

## 2. Criação de convite

- [x] 2.1 Model `Invitation` com normalização `email.strip.downcase` em
  `before_validation`, geração de `token` (`rt_inv_` + `SecureRandom.urlsafe_base64(32)`)
  e `expires_at` = `created_at + 7.days` (§3.10 — convite criado com
  `"Joao@Fabrica.COM"` é persistido como `"joao@fabrica.com"` e casa no aceite)
- [x] 2.2 `InvitationPolicy` no mecanismo de `authorization-policies` (D3):
  `create?`/`destroy?`/`index?` exigem membership `owner` do workspace-alvo
  (§4.1 inv. 7 — membro `edit` recebe `403` e nenhuma linha é criada)
- [x] 2.3 `Invitations::CreateService` no contrato `ApiResponseHandler`, retornando
  o link absoluto montado com `ENV['APP_URL']`; rejeitar `role: "owner"` com `422
  invalid_role` e e-mail > 254 chars com `422 invalid_email` (§3.10 — a resposta
  contém a URL completa `<APP_URL>/convite/rt_inv_...`, não só o token solto)
- [x] 2.4 Endpoints Grape `POST /api/v1/invitations`, `GET /api/v1/invitations`
  (pendentes do workspace corrente), `DELETE /api/v1/invitations/:id`, montados com
  uma linha em `api/v1/base.rb`; `Api::Entities::Invitation` **nunca** serializa o
  `token` em respostas de listagem sem o link (§3.10 — a lista de pendentes permite
  recopiar o link)
- [x] 2.5 Request spec dos caminhos negativos de criação: `edit` convidando, `view`
  convidando, `workspace_id` de outro workspace, `role: "owner"`, e-mail de 255
  chars (verificação do grupo 2 — todos `403`/`422`, contagem de `invitations`
  inalterada em todos os cinco)

## 3. Consumo atômico

- [x] 3.1 `Invitations::AcceptService`: transação com `lock('FOR UPDATE')` e as seis
  validações da invariante 6 na ordem de D-INV-3, cada uma com código de erro HTTP
  distinto (§4.1 inv. 6 — `404`/`409`/`410`/`422`/`403`/`422`, nunca um `422`
  genérico que impeça o cliente de distinguir "expirado" de "e-mail errado")
- [x] 3.2 Resolução de `Person` dentro da mesma transação (D-INV-5): casar por
  e-mail com `user_id IS NULL`, ou criar nova; `409 person_email_conflict` se já
  vinculada a outro usuário (D10 — responsável pré-cadastrado com 12 tarefas
  mantém as 12 tarefas após o aceite, não vira uma segunda `Person`)
- [x] 3.3 Endpoint `POST /api/v1/invitations/:token/accept` que **rejeita** `role`
  no corpo com `422 unexpected_parameter` em vez de ignorar (§4.1 inv. 6 — enviar
  `{"role":"edit"}` num convite `view` retorna erro e não consome o convite)
- [x] 3.4 Endpoint público `GET /api/v1/invitations/:token` com `email_masked`,
  adicionado à allowlist de regex de `api/root.rb` (§3.10 — a resposta não contém
  `joao@fabrica.com`, `workspace_id` nem lista de membros; só
  `j***@fabrica.com`)
- [x] 3.5 Spec de concorrência: duas threads com conexões distintas aceitando o
  mesmo token simultaneamente (§4.1 inv. 6 — exatamente um `200` e um `409
  invitation_already_used`; `Membership.where(invitation_id:).count == 1`; nenhum
  `500` e nenhum deadlock)
- [x] 3.6 Spec de carga: 50 aceites concorrentes de 50 tokens **distintos** dentro
  do `statement_timeout` configurado (verificação do grupo 3 — o `FOR UPDATE` não
  serializa tokens diferentes; se serializar, o teste estoura o timeout)

## 4. Painel de equipe

- [x] 4.1 `MembershipPolicy` + `Memberships::UpdateRoleService`: só `owner`, só
  entre `view`/`edit`, `422 owner_is_immutable` se o alvo for o dono (§4.1 inv. 5 —
  `PATCH` com `role: "owner"` retorna `422` e o papel não muda)
- [x] 4.2 Backup: antes de qualquer remoção de membro, `Memberships::RemoveService`
  grava snapshot da membership (workspace, person, role, invitation_id) numa
  entrada de `audit_logs` (§2.8 — a remoção é reversível manualmente pelo dono a
  partir do log, já que `audit_logs` tem `REVOKE UPDATE, DELETE` por D12)
- [x] 4.3 `Memberships::RemoveService`: remove a membership, limpa `person.user_id`
  para `NULL` e **não** apaga a `Person` (§3.10 — as 12 tarefas do removido
  continuam apontando para a mesma `Person`; `422 cannot_remove_owner` se o alvo
  for o dono)
- [x] 4.4 Endpoints `GET /api/v1/memberships`, `PATCH /api/v1/memberships/:id`,
  `DELETE /api/v1/memberships/:id` com policy declarada, cobertos pelo route-sweep
  de D3 (§4.1 inv. 1 — o route-sweep falha o CI se algum dos três não declarar policy)
- [ ] 4.5 Componente `features/team/TeamPanel` com as duas listas e chaves React
  Query `['ws', wsId, 'members']` e `['ws', wsId, 'invitations']` (D9) (§3.10 —
  membro `edit` vê as listas sem nenhum botão de mutação renderizado)
- [ ] 4.6 Diálogo de criação de convite com "Copiar link" e fallback de campo
  selecionável quando a Clipboard API é negada (§3.10 — negar a permissão de
  clipboard mostra o link em texto, não uma falha silenciosa)
- [x] 4.7 Request spec negativo do painel: `view` fazendo `PATCH` de papel, `edit`
  fazendo `DELETE` de convite, dono de `WS-A` mexendo em membership de `WS-B`
  (verificação do grupo 4 — os dois primeiros `403`, o terceiro `404` porque a RLS
  esconde a linha; `404` e não `403` é o critério, senão a existência de `WS-B`
  vaza)

## 5. Fluxo do convidado e revogação em tempo real

- [ ] 5.1 Rota pública `/convite/:token` que grava o token em `sessionStorage`,
  chama `history.replaceState` para limpar a URL e exibe a pré-visualização
  (§3.10 — o histórico do navegador não contém `rt_inv_ABC` depois da montagem)
- [ ] 5.2 Consumo pós-autenticação no shell: dispara o aceite quando há token e
  sessão, e limpa `sessionStorage` em **qualquer** desfecho (§3.10 — após um
  `403 invitation_email_mismatch`, navegar para outra tela não reemite o aceite)
- [ ] 5.3 Rotina única `handleAccessRevoked(wsId)` no cliente: aviso persistente,
  remoção do índice local, `queryClient.removeQueries(['ws', wsId])` e navegação ao
  workspace próprio; acionada pelo 403 `workspace_access_revoked` do interceptor do
  `apiClient` (§3.10 — sem Cable conectado, a revogação ainda é detectada na
  próxima requisição e nenhum dado de `WS-A` permanece na tela)
- [x] 5.4 Publicação do evento `membership_revoked` no `WorkspaceChannel` a partir
  de `Memberships::RemoveService`, consumido por `handleAccessRevoked` (D6 — com
  Cable conectado, a detecção ocorre em < 2s sem interação do usuário; a tarefa
  degrada para no-op se `realtime-collaboration` ainda não estiver entregue)
- [ ] 5.5 E2E do fluxo completo: dono convida → copia link → convidado abre sem
  sessão → autentica → vira membro → dono remove → convidado é expulso ao vivo
  (verificação do grupo 5 — o convidado termina no workspace próprio com aviso
  visível, e um reload não o traz de volta a `WS-A`)

## 6. Operação e endurecimento

- [ ] 6.1 `Rack::Attack` com store Redis: 10/10min por IP e por usuário no aceite,
  20/10min por IP na pré-visualização, `429` com `Retry-After`, e log estruturado
  de bloqueio com SHA-256 do token truncado em 12 chars (§3.10 — a 11ª tentativa
  retorna `429` sem tocar o banco, verificado por contagem de queries; e
  `grep 'rt_inv_' log/` após 20 bloqueios não retorna nada)
- [ ] 6.2 `Invitations::PurgeExpiredJob` agendado diariamente, apagando só
  `used_at IS NULL AND expires_at < now() - 30 days` (§3.10 — convite expirado há
  3 dias sobrevive e produz `410`; convite consumido há 2 anos sobrevive porque
  `ON DELETE RESTRICT` o protege)
- [ ] 6.3 Declarar a `APP_URL` obrigatória e o agendamento do Sidekiq em produção
  junto a `delivery-and-observability`, com header `Referrer-Policy: no-referrer`
  na rota `/convite/:token` (§3.10 — sem `APP_URL`, o boot falha explicitamente em
  vez de gerar links com `localhost` em produção)
- [ ] 6.4 Strings pt-BR de convite, erro e revogação em `config/locales/pt-BR.*.yml`
  e no módulo único do frontend (D14 — nenhum literal de mensagem de convite fora
  dos dois arquivos, verificado por grep no CI)
- [ ] 6.5 Suíte executável das invariantes 6 e 7 contribuída à suíte de
  `authorization-policies`, com os seis cenários de negação obrigatórios
  (verificação do grupo 6 — e-mail divergente, token usado, expirado, papel
  adulterado, workspace alheio e `edit` convidando falham cada um com seu código
  distinto; um `422` genérico para todos reprova)
