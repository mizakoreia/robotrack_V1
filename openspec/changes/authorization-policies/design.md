## Context

Duas fontes descrevem a autorização do RoboTrack e **elas não são redundantes**:

1. `ESPECIFICACAO.md §4.1` — a matriz de 8 ações × 3 papéis e as 8 invariantes.
   É a intenção de produto.
2. `firestore.rules` — a implementação versionada que rodava em produção. Codifica
   semânticas que a matriz não expressa.

Onde as duas divergem, a rule é mais específica e a matriz é mais correta. Exemplos
concretos levantados na leitura linha a linha:

| `firestore.rules` | O que a §4.1 diz | Resolução no porte |
|---|---|---|
| L61-62: `update` de notificação exige `affectedKeys().hasOnly(['read'])`, para **qualquer** membro | inv. 4 fala só do papel `view` | Adotar a rule: a restrição de colunas vale para todos, inclusive `owner`. Vira **trigger**. |
| L61: qualquer membro pode marcar **qualquer** notificação como lida | inv. 4 diz "a **própria** notificação" | Adotar a §4.1 — endurecimento. Divergência D-A abaixo. |
| L16-20: papel do dono é inferido de `request.auth.uid == wsId` | inv. 2: papel vem **exclusivamente** da associação de membro | Adotar a §4.1. O dono é uma `membership` com `role='owner'`. Divergência D-B. |
| L18-19: membro `edit` pode dar `update` no workspace desde que não mude `ownerUid` | matriz: "excluir workspace / reset" é só `owner`; renomear workspace não aparece | Renomear/tema = ação `manage_catalog` (edit pode). Destruir/reset = `destroy_workspace` (só owner). `owner_person_id` imutável por trigger (inv. 5). |
| L84: `users/{uid}` livre para o próprio | inv. 2: índice de UI, não fonte de autorização | Mantido como cache de UI. Nenhuma policy lê essa tabela. |
| L67-82: `invites` | inv. 6 e 7 | Policies aqui; atomicidade do consumo em `workspace-invitations`. |

Estado do template ai9 relevante: Grape em `app/controllers/api/`, um único `before`
em `api/root.rb` com allowlist pública por regex, services singleton com
`ApiResponseHandler` retornando `{success:, data:, status:}`, `process_service_response`
em `api/v1/controller_helpers.rb`. **Não existe Pundit/CanCan.** Existe um gate
`User#og?`/`#client?` inline e um RBAC de plano de cobrança que ninguém consome de
forma sistemática — a exata configuração em que a invariante 1 apodrece sem que
nenhum teste vermelhe.

Dependências duras: `workspace-tenancy` entrega `workspaces`, `people`,
`memberships` e a RLS com `app.current_workspace_id` (D2/D10);
`identity-and-auth` entrega `current_user` confiável (D4);
`seal-template-baseline` veda `X-Skip-Auth` e cria `spec/factories` + helper de auth
de request. Sem os três, nada aqui roda.

## Goals / Non-Goals

**Goals**

- Uma decisão de autorização por request, tomada em **um** lugar, antes do service.
- A matriz §4.1 legível como tabela num único arquivo, comparável visualmente com a
  spec por um humano em 30 segundos.
- Impossibilidade **mecânica** de adicionar endpoint sem policy.
- As 8 invariantes executáveis de uma vez, por HTTP, com nomes que citam o número.
- Vazamento entre tenants provado ausente endpoint a endpoint, não por amostragem.
- Cada `allow` do `firestore.rules` rastreável a um teste ou a uma divergência escrita.

**Non-Goals**

- Autorização por atributo/linha além de tenant + papel. RoboTrack tem 3 papéis e
  nenhum requisito de ACL por recurso; não construir motor de permissão genérico.
- Delegação/impersonação, papéis customizados, permissões por projeto. Fora da §4.1.
- Gating de UI, cache de decisão, auditoria da decisão de autorização (o
  `audit_logs` da §2.8 audita ações de domínio, não negações).
- Rate limiting de tentativas negadas (é `rack-attack`, de `delivery-and-observability`).

## Decisions

### D3.1 — Policy objects singleton, não Pundit

Cada policy é `module Policies; class ProjectPolicy < BasePolicy; class << self ...`
com predicados que recebem `(context, resource = nil)` e devolvem booleano, e um
`authorize!` que levanta `Authorization::Forbidden`. Espelha exatamente o idioma dos
services do template.

*Alternativa descartada*: **Pundit**. Pundit assume `current_user` + um objeto de
controller ActionController e resolve policy por convenção de classe do record. Em
Grape não há controller; o `policy` helper teria de ser reimplementado à mão, e o
`verify_authorized` (que seria o análogo do route-sweep) roda **por request em
runtime**, não por rota em CI — ou seja, só pega o endpoint desprotegido se algum
teste bater nele. O que queremos é justamente pegar o endpoint que **nenhum** teste
bate. O acoplamento não paga. *Alternativa descartada*: **CanCanCan** — `Ability`
única e monolítica; a matriz §4.1 ficaria num arquivo de 200 linhas de DSL onde a
comparação visual com a spec é impossível.

### D3.2 — A matriz §4.1 é dado, não código

`backend/app/policies/permission_matrix.rb` contém literalmente:

```
ACTIONS = {
  read_workspace:      %i[owner edit view],
  manage_commissioning:%i[owner edit],
  record_progress:     %i[owner edit],
  manage_catalog:      %i[owner edit],
  create_log:          %i[owner edit],
  mark_notification_read: %i[owner edit view],
  manage_membership:   %i[owner],
  destroy_workspace:   %i[owner]
}.freeze
```

Oito chaves, uma por linha da tabela §4.1, na mesma ordem. Toda policy de recurso
mapeia suas operações para uma dessas 8 actions; **nenhuma policy compara papel
diretamente**. Um teste da suíte de conformidade reafirma as 8 linhas literalmente,
de modo que mudar a matriz exige mudar dois lugares — o segundo sendo um teste que
cita a §4.1.

*Alternativa descartada*: predicado por método em cada policy (`create?`, `update?`).
Espalha a matriz por 9 arquivos e torna impossível auditar "quem pode reordenar?"
sem grep.

### D3.3 — `Authorization::Context` é a única origem de papel (inv. 2)

Objeto imutável construído uma vez por request no `before` de `Api::Root`, **depois**
da autenticação: `user` (de D4), `workspace` (do header/rota, resolvido por
`workspace-tenancy`), `person` e `role` — este último lido **só** de
`memberships WHERE workspace_id = ? AND person_id = ?`. Se não houver membership, o
contexto nasce com `role = nil` e toda policy nega; a resposta é **404**, não 403
(D3.6). Nenhuma policy tem acesso a `User` para decidir papel, e nenhuma lê a tabela
de índice de workspaces do usuário.

*Onde a invariante mora*: `memberships` com `UNIQUE (workspace_id, person_id)` +
`role` como enum Postgres `membership_role ('owner','edit','view')` (constraint, não
validação de model) + a RLS de D2 impedindo até a leitura de linhas de outro
workspace. O `Context` é conveniência de leitura; a garantia é do banco.

### D3.4 — Declaração de policy por rota + fail-closed

Cada endpoint declara `route_setting :policy, { policy: Policies::ProjectPolicy, action: :update }`.
O `before` global lê `env['api.endpoint'].route_setting(:policy)`. Se ausente:

- `Rails.env.development?` / `test?` → levanta `Authorization::UndeclaredRouteError`
  (falha barulhenta, na cara de quem escreveu o endpoint);
- `production` → responde 500 e reporta ao rastreio de erro, **nunca** 200.

Fail-closed em produção é deliberado: um endpoint sem policy é um bug de segurança,
e servir dados é pior do que servir erro.

*Alternativa descartada*: default `:authenticated` para rotas não declaradas.
Transforma esquecimento em silêncio, que é precisamente o modo de falha do template.

### D3.5 — Route-sweep em CI, não em runtime

`spec/authorization/route_sweep_spec.rb` itera `Api::Root.routes` e para cada rota
exige **ou** um `route_setting(:policy)` **ou** uma entrada em
`config/authorization/public_routes.yml`. A allowlist é YAML com `path`, `method` e
um campo `reason` obrigatório e não-vazio — obrigar a escrever o motivo é o custo que
desencoraja usar a allowlist como escape hatch. O mesmo spec falha se a allowlist
tiver entrada **órfã** (rota que não existe mais), para que ela não acumule permissão
morta. A mensagem de falha lista método + path das rotas ofensoras, uma por linha.

*Alternativa descartada*: `verify_authorized` estilo Pundit (após cada request em
teste). Só cobre rotas exercitadas por algum teste — inútil contra endpoint novo e
não testado, que é o caso perigoso.

### D3.6 — Recurso de outro tenant responde 404, nunca 403

403 confirma existência. Para qualquer id que não pertença ao workspace do contexto,
a resposta é `404` com o mesmo corpo de "não encontrado" de um id inexistente. 403
fica reservado a **recurso do meu workspace, papel insuficiente** — aí a existência
já é conhecida por quem pede (`view` lê tudo, §4.1 linha 1).

*Onde a invariante mora*: a RLS de D2 já torna a linha invisível ao `SELECT`, então o
404 cai naturalmente do `find`. A policy é a segunda camada. A varredura negativa
prova as duas juntas.

### D3.7 — Invariante 4 vira trigger, e o alvo é o destinatário

Porte de `affectedKeys().hasOnly(['read'])`. Duas metades:

- **Colunas**: trigger `BEFORE UPDATE ON notifications` que levanta se qualquer
  coluna além de `read`, `read_at` e `updated_at` mudou. Vale para **todos os
  papéis, inclusive `owner`** — é o que a rule legada dizia. Não é validação de
  model: um `update_column` no console tem de falhar.
- **Alvo**: `NotificationPolicy.mark_read?` exige `notification.person_id ==
  context.person.id`. **Divergência D-A**: a rule legada permitia a qualquer membro
  marcar a notificação alheia; a §4.1 inv. 4 diz "a **própria**". Adotamos a §4.1;
  a rule é tratada como fraqueza do legado, não como requisito.

### D3.8 — Dono imutável por trigger (inv. 5)

Trigger `BEFORE UPDATE ON workspaces` levanta se `owner_person_id` mudou, e índice
único parcial `UNIQUE (workspace_id) WHERE role = 'owner'` em `memberships` garante
exatamente um dono. Não existe action `transfer_ownership` na matriz — não há caminho
de API sequer nominal. **Divergência D-B** com a rule legada, que inferia dono de
`request.auth.uid == wsId`: no porte o dono é uma linha de `memberships`, o que faz a
inv. 2 valer sem exceção (a rule legada tinha o dono como *exceção* à inv. 2).

### D3.9 — Auditoria: policy sem verbo de escrita (inv. 3)

`AuditLogPolicy` expõe `index?`/`show?` (action `read_workspace`) e `create?`
(action `create_log`) — e **nenhum** `update?`/`destroy?`. A ausência é intencional e
testada: o teste da invariante 3 chama `PATCH`/`DELETE` como **`owner`** e espera
`405`/`404` de rota inexistente, e adicionalmente prova no banco que
`REVOKE UPDATE, DELETE` (de `audit-log`) está ativo. Append-only para todos inclui o
dono — foi por isso que a rule legada escreveu `allow update, delete: if false`.

### D3.10 — Varredura negativa gerada, não escrita à mão

`spec/authorization/cross_tenant_spec.rb` deriva os casos da mesma tabela de rotas do
sweep: toda rota cujo path contém um segmento `:id`/`:*_id` gera um exemplo que
autentica como membro do workspace B e endereça um recurso semeado no workspace A,
esperando 404. Rotas que não se encaixam no gerador entram num mapa explícito
`cross_tenant_overrides.yml` — e uma rota sem gerador **e** sem override falha o
spec. Assim um endpoint novo herda o teste negativo automaticamente.

### D3.11 — Checklist de paridade com `firestore.rules`

`spec/authorization/legacy_parity_spec.rb` carrega
`config/authorization/legacy_parity.yml`, que tem uma entrada por `allow` do arquivo
legado (path da rule, verbo, número da linha) e, para cada uma, ou o id do exemplo
RSpec que a cobre, ou uma `divergence:` com texto. O spec falha se alguma entrada não
tiver nem cobertura nem divergência. Isso é o "linha a linha, não de memória".

### D3.12 — Contrato de erro

Negação nunca vaza detalhe: `403 {"error":"forbidden"}`, `404 {"error":"not_found"}`,
`401 {"error":"unauthorized"}`. Mensagens pt-BR vêm de `config/locales/pt-BR.*.yml`
(D14). O corpo **não** inclui papel exigido nem nome de policy.

## Onde cada invariante mora

| Inv. | §4.1 | Mecanismo primário | Reforço |
|---|---|---|---|
| 1 | authz no servidor | `before` fail-closed em `Api::Root` (D3.4) | route-sweep em CI (D3.5) |
| 2 | papel só da membership | enum PG + `UNIQUE (workspace_id, person_id)` + RLS (D2) | `Authorization::Context` (D3.3) |
| 3 | log append-only | `REVOKE UPDATE, DELETE` (cap. `audit-log`) | policy sem verbo de escrita (D3.9) |
| 4 | só `read` muda | trigger `BEFORE UPDATE ON notifications` (D3.7) | `NotificationPolicy` checa destinatário |
| 5 | dono imutável | trigger em `workspaces` + índice único parcial (D3.8) | matriz sem action de transferência |
| 6 | consumo atômico de convite | transação + `UNIQUE` em `invitations.token` (cap. `workspace-invitations`) | `InvitationPolicy.consume?` |
| 7 | convite no próprio ws, papel `view`/`edit` | `CHECK role IN ('view','edit')` em `invitations` | `InvitationPolicy.create?` força `workspace_id` do contexto |
| 8 | notificação ≤500, `read:false` | `CHECK char_length(message) <= 500` + `DEFAULT false` (cap. `in-app-notifications`) | policy ignora `read` no create |

Invariantes 6, 7 e 8 têm mecanismo primário fora desta capacidade. A suíte executável
mora **aqui** e falha se o mecanismo de lá não existir — é o que impede a
invariante de cair no vão entre duas capacidades, que foi o que aconteceu no WBS
anterior.

## Plano de migração

Três migrations, todas aditivas e reversíveis:

1. `add_owner_immutability_to_workspaces` — trigger + função. `down` faz `DROP TRIGGER`.
2. `add_single_owner_index_to_memberships` — índice único parcial. Exige que
   `workspace-tenancy` já tenha garantido um `owner` por workspace; a migration roda
   uma checagem prévia e **aborta com contagem** se houver workspace com 0 ou 2+
   donos, em vez de falhar no meio da criação do índice.
3. `add_read_only_mutation_trigger_to_notifications` — depende de
   `in-app-notifications` ter criado a tabela. Se a tabela não existir, a migration é
   no-op registrada e a suíte de invariantes falha na inv. 4 até a tabela chegar.

Nenhuma é destrutiva; nenhuma toca dados. Não há backup necessário. A ordem entre
capacidades é: `workspace-tenancy` → migrations 1 e 2 → (mais tarde)
`in-app-notifications` → migration 3.

O rollout do `route_setting :policy` é o único passo com risco de quebrar tudo de
uma vez. Faseamento: (a) mergear o `before` com o comportamento fail-closed atrás da
env var `AUTHZ_ENFORCE=1`, ligada em `test` desde o dia 1; (b) declarar policies
endpoint a endpoint até o route-sweep ficar verde; (c) remover a env var e tornar o
fail-closed incondicional. A tarefa de remoção da flag é explícita em `tasks.md` para
que a fase (b) não vire permanente. Citar `delivery-and-observability` para a env var.

## Risks / Trade-offs

- **A allowlist pública vira porta dos fundos.** Mitigação: `reason` obrigatório,
  entradas órfãs falham o spec, e a lista é enumerada num teste que a imprime — a
  revisão vê a lista crescer. Risco residual aceito.
- **Fail-closed em produção derruba endpoint esquecido.** Trade-off assumido: 500 é
  melhor que vazamento. Mitigado porque o route-sweep torna o esquecimento
  detectável antes do deploy — o 500 só acontece se alguém pular o CI.
- **Duas camadas (RLS + policy) podem discordar.** Se a RLS esconde e a policy
  permitiria, o resultado é 404 — seguro. O contrário (policy nega, RLS permite)
  também é seguro. O risco real é *confiar* em uma e afrouxar a outra; por isso a
  varredura negativa testa via HTTP, com as duas ligadas, e existe um teste que
  desliga a policy e prova que a RLS sozinha ainda dá 404.
- **A matriz de 8 actions é grossa demais para requisitos futuros** (ex.: "editor
  pode reordenar mas não excluir projeto"). É exatamente o que a §4.1 pede hoje.
  Se um requisito assim aparecer, quebra-se `manage_commissioning` em duas actions —
  o custo é uma linha na matriz e um teste, porque nenhuma policy compara papel.
- **O gerador de testes cross-tenant tem falso negativo** em rota que identifica
  recurso por corpo, não por path. Mitigação: `cross_tenant_overrides.yml` obrigatório,
  e rota sem gerador nem override falha.
- **Dependência de trabalho ainda não feito**: as invariantes 3, 6, 7 e 8 falham
  legitimamente enquanto `audit-log`, `workspace-invitations` e `in-app-notifications`
  não existirem. Trade-off aceito e deliberado — a suíte é o *marcador de dívida* que
  faltava. Ela roda com essas quatro marcadas `pending` **com motivo nomeando a
  capacidade responsável**, e uma tarefa em cada uma daquelas capacidades remove o
  `pending`. `pending` sem motivo falha o meta-spec.

## Perguntas em aberto

1. `view` pode **criar** notificação para si mesmo? A §4.1 diz não (linha "criar log
   / notificação" = `owner`/`edit`); nenhuma feature descrita gera esse caso. Assumido
   **não**; revisar se `in-app-notifications` precisar.
2. Renomear workspace / trocar tema: mapeado em `manage_catalog` (`edit` pode), por
   analogia com a rule legada L18-19 que permitia `update` a `edit`. Se
   `workspace-settings` decidir que renomear é ato de dono, é uma linha na matriz.
3. Papel `owner` como membership implica que remover a própria membership de dono é
   impossível — o índice único parcial garante. Excluir o workspace continua sendo o
   único caminho de saída do dono. Confirmar com `workspace-settings`.
