# Tarefas — authorization-policies

Pré-requisitos duros (não são tarefas desta capacidade): `workspace-tenancy`
(workspaces/people/memberships + RLS, D2/D10), `identity-and-auth` (JWT real, D4) e
`seal-template-baseline` (`X-Skip-Auth` vedado, `spec/factories`, helper de auth de
request). Cada grupo abaixo termina em verificação.

## 1. Núcleo de autorização

- [x] 1.1 Criar `backend/app/policies/permission_matrix.rb` com as 8 actions da §4.1
      na ordem da tabela, congelado, e `PermissionMatrix.allows?(action, role)`.
      (§4.1 tabela — `allows?(:manage_membership, :edit)` retorna `false`; qualquer
      action desconhecida levanta `KeyError`, não retorna `false` silenciosamente)

- [x] 1.2 Criar `backend/app/lib/authorization/context.rb`: objeto imutável
      `(user, workspace, person, role)`, com `role` lido **só** de `memberships`.
      (§4.1 inv. 2 — um contexto construído para usuário sem membership tem
      `role == nil` e `Context#member?` `false`; o construtor não aceita `role` por
      argumento, então nenhum chamador pode injetá-lo)

- [x] 1.3 Criar `backend/app/policies/base_policy.rb` no idioma singleton dos
      services (`class << self`), com `authorize!(context, action, resource = nil)`
      levantando `Authorization::Forbidden` / `Authorization::NotFound`.
      (D3.1 — `BasePolicy` não expõe leitura de `role`; uma subclasse que tente
      `context.role == :owner` é pega pelo cop do grupo 6)

- [x] 1.4 Escrever as policies de recurso: `ProjectPolicy`, `CellPolicy`,
      `RobotPolicy`, `TaskPolicy`, `AdvancePolicy`, mapeando cada operação para uma
      das 8 actions. (§4.1 linhas 2-3 — `ProjectPolicy.destroy?` com papel `edit`
      retorna `true`, com `view` retorna `false`, e nenhuma delas compara `role`)

- [x] 1.5 Escrever `TaskTemplatePolicy`, `PersonPolicy`, `AuditLogPolicy`,
      `NotificationPolicy`, `MembershipPolicy`, `InvitationPolicy`, `WorkspacePolicy`.
      (§4.1 linhas 4-8 — `AuditLogPolicy` não responde a `update?`/`destroy?`:
      `respond_to?(:update?)` é `false`, não um método que retorna `false`)

- [x] 1.6 Spec unitário de `PermissionMatrix` que reafirma as 8 linhas literalmente,
      com o texto da §4.1 em comentário ao lado de cada linha.
      (§4.1 — trocar `mark_notification_read` para `[:owner, :edit]` quebra este spec
      com diff legível, não um erro de integração distante)

## 2. Gate no Grape

- [ ] 2.1 Criar `api/v1/authorization_helpers.rb` com `authorize!` que lê
      `route_setting(:policy)` do endpoint corrente.
      (D3.4 — endpoint sem `route_setting` faz o helper levantar
      `Authorization::UndeclaredRouteError`, não retornar `nil`)

- [ ] 2.2 Ligar a etapa de autorização no `before` de `api/root.rb`, depois da
      autenticação, atrás de `AUTHZ_ENFORCE`, com a flag ligada em `test` desde já e
      um spec afirmando que ela está ligada nesse ambiente.
      (§4.1 inv. 1 — com um service instrumentado, uma requisição negada registra
      zero invocações do service; e desligar a flag em `test` vermelha um spec, então
      o rollout faseado não se torna permanente por inércia)

- [ ] 2.3 Implementar o comportamento fail-closed por ambiente: levanta em
      `development`/`test`, responde `500` + rastreio de erro em `production`.
      (D3.4 — rota não declarada em produção responde `500` com corpo sem dado de
      domínio; nunca `200`)

- [ ] 2.4 Mapear as exceções de autorização em `rescue_from` para o contrato
      `401`/`403`/`404` com corpo de chave única `error`, strings de
      `config/locales/pt-BR.*.yml` (D14).
      (§4.1 — o corpo do `403` não contém `"owner"`, `"edit"`, `"ProjectPolicy"` nem
      o nome da action)

- [ ] 2.5 Criar `config/authorization/public_routes.yml` com `path`/`method`/`reason`
      obrigatórios, carregado uma vez no boot.
      (D3.5 — entrada com `reason` vazio faz o boot falhar em `test`, não passar
      despercebida)

- [ ] 2.6 Declarar `route_setting :policy` em todos os endpoints Grape sobreviventes
      ao `seal-template-baseline`. (§4.1 inv. 1 — o route-sweep do grupo 5 passa a
      verde; enquanto sobrar um endpoint, ele lista o método + path exatos)

- [ ] 2.7 Spec de request provando que `X-Skip-Auth: 1` não contorna autorização.
      (§4.1 inv. 1 — Diego com o header em `GET /workspaces/WS-A/projects` recebe
      `401` ou `404`, nunca a lista de projetos; regressão contra a brecha do template)

## 3. Invariantes no banco

- [ ] 3.1 Migration: trigger `BEFORE UPDATE ON workspaces` que levanta se
      `owner_person_id` mudar; `down` faz `DROP TRIGGER` e `DROP FUNCTION`.
      (§4.1 inv. 5 — `UPDATE workspaces SET owner_person_id=...` direto no psql aborta
      a transação; testar por SQL, não pelo model)

- [ ] 3.2 Migration: índice único parcial `UNIQUE (workspace_id) WHERE role='owner'`
      em `memberships`, precedida no mesmo arquivo por checagem que **aborta com a
      contagem** se algum workspace tiver 0 ou 2+ donos.
      (§4.1 inv. 5 — promover Bruno a `owner` em WS-A viola o índice; e a migration
      não cria índice pela metade em base suja, ela recusa e diz quantas linhas)

- [ ] 3.3 Migration: trigger `BEFORE UPDATE ON notifications` rejeitando mudança de
      qualquer coluna além de `read`, `read_at`, `updated_at` — para todos os papéis.
      No-op registrado se a tabela ainda não existir.
      (§4.1 inv. 4 / `firestore.rules` L61-62 — `Notification#update_column(:message,…)`
      executado como o dono do workspace levanta exceção do Postgres)

- [ ] 3.4 Implementar em `NotificationPolicy.mark_read?` a checagem de destinatário
      (`notification.person_id == context.person.id`) e restringir os params do
      endpoint a `read`. (§4.1 inv. 4 — Clara marcando `N-BRUNO` recebe `403`;
      `{"read":true,"message":"x"}` recebe `422` e não aplica nem o `read`)

- [ ] 3.5 Spec de banco cobrindo os três objetos DDL via SQL cru, sem passar por
      ActiveRecord. (§4.1 inv. 4 e 5 — os testes falham se alguém remover o trigger e
      mantiver só a validação de model)

## 4. Isolamento entre tenants

- [ ] 4.1 Padronizar a resolução de recurso para `404` fora do tenant: helper de
      lookup escopado por `Authorization::Context#workspace`, usado por todos os
      endpoints. (D3.6 — `GET /workspaces/WS-A/robots/R-B1` responde `404` com corpo
      byte-a-byte igual ao de um UUID aleatório)

- [ ] 4.2 Escrever `spec/authorization/cross_tenant_spec.rb` com o gerador que deriva
      um exemplo por rota com id, mais `cross_tenant_overrides.yml`.
      (D3.10 — um `PATCH /robots/:id` implementado com `Robot.find` sem escopo faz o
      spec falhar por receber `200` onde esperava `404`)

- [ ] 4.3 Spec que desliga a avaliação de policy e prova que a RLS sozinha ainda
      devolve `404`. (D2/D3.6 — se alguém remover a RLS confiando na policy, este é o
      único teste que vermelha)

- [ ] 4.4 Spec de listagem: header `X-Total-Count` reflete só o tenant corrente.
      (§4.1 inv. 1 — com 12 projetos em WS-A e 3 em WS-B, Diego recebe `3`, não `15`;
      pega o vazamento por contagem que o corpo paginado esconderia)

## 5. Suíte de conformidade

- [ ] 5.1 Escrever `spec/authorization/route_sweep_spec.rb` com a asserção de
      igualdade `policies + allowlist == Api::Root.routes.size`, mensagem listando as
      ofensoras uma por linha, e detecção de entrada órfã na allowlist.
      (D3.5 — montar um `GET /workspaces/:workspace_id/gadgets` sem declaração falha
      citando esse path exato; e a entrada de `/auth/v1/magic_login/request_code`,
      cuja rota o `seal-template-baseline` removeu, falha em vez de virar permissão
      morta)

- [ ] 5.2 Criar `spec/authorization/invariants/` com os 8 arquivos numerados e
      `invariants_completeness_spec.rb` contando 8.
      (§4.1 — excluir `inv_5_owner_immutable_spec.rb` faz o meta-spec falhar por
      contar 7; e `pending` sem motivo nomeando a capacidade bloqueadora também falha)

- [ ] 5.3 Implementar `inv_1`, `inv_2`, `inv_4` e `inv_5` — as quatro que esta
      capacidade fecha sozinha — por HTTP.
      (§4.1 inv. 1/2/4/5 — `inv_2` prova que JWT com claim `role:"owner"` e índice de
      UI adulterado não concedem nada)

- [ ] 5.4 Implementar `inv_3`, `inv_6`, `inv_7` e `inv_8` como provas reais, marcadas
      `pending` com motivo enquanto `audit-log`, `workspace-invitations` e
      `in-app-notifications` não existirem.
      (§4.1 inv. 3/6/7/8 — `inv_8` falha se um `INSERT` com `message` de 501 chars for
      aceito; `inv_3` falha se `audit_logs` ainda aceitar `UPDATE` do papel da app)

- [ ] 5.5 Escrever a matriz completa de request specs papel × ação: 3 papéis × as 8
      linhas da §4.1, com maioria de casos negativos.
      (§4.1 tabela — Bruno (`edit`) recebe `403` em `POST /invitations`,
      `PATCH /memberships/<clara>`, `DELETE /workspaces/WS-A` e `POST /factory_reset`)

- [ ] 5.6 Portar `firestore.rules` para `config/authorization/legacy_parity.yml`,
      uma entrada por `allow`, com a contagem conferida pelo spec.
      (D3.11 — omitir a entrada de L61-62 faz a contagem divergir e o spec falhar;
      não dá para esquecer uma rule)

- [ ] 5.7 Escrever `legacy_parity_spec.rb` exigindo `covered_by` ou `divergence` por
      entrada, e imprimindo o relatório de divergências.
      (D3.11 — as divergências D-A (notificação alheia) e D-B (dono por uid) aparecem
      no output com texto, em vez de sumirem na tradução)

## 6. Fechamento e entrega

- [ ] 6.1 Adicionar cop/spec estático que proíbe comparação direta de papel fora de
      `permission_matrix.rb` (`context.role ==`, `role == :owner`).
      (D3.2 — um `if context.role == :owner` numa policy nova falha o build; é o que
      impede a matriz de voltar a se espalhar em `if`s)

- [ ] 6.2 Configurar o job de CI `authorization` rodando `spec/authorization/` isolado
      e bloqueante; citar em `delivery-and-observability`.
      (§4.1 inv. 1 — route-sweep vermelho com os outros 400 testes verdes ainda
      bloqueia o merge, nomeado como falha de autorização)

- [ ] 6.3 Remover a flag `AUTHZ_ENFORCE` e tornar o fail-closed incondicional, depois
      que 5.1 estiver verde. (D3.4 — nenhuma referência à env var resta no código; o
      grep por `AUTHZ_ENFORCE` retorna zero ocorrências fora do CHANGELOG)

- [ ] 6.4 Rodar a suíte inteira com um seed de 2 workspaces × 3 papéis e registrar o
      relatório de conformidade (8 invariantes + sweep + cross-tenant + paridade).
      (§4.1 — o relatório nomeia cada invariante ainda `pending` e a capacidade que a
      bloqueia; nenhuma invariante fica sem status)
