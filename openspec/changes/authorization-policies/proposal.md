## Why

A §4.1 da ESPECIFICACAO.md é a única seção da spec que descreve um contrato de
*segurança*, e não de produto: três papéis (`owner` / `edit` / `view`), uma matriz
de 8 linhas e **8 invariantes obrigatórias na reimplementação**. No legado essas
regras moravam em `firestore.rules` — versionadas, mas expressas num dialeto que o
porte não tem. Traduzi-las "de cabeça" perde semântica: a rule de notificações não
diz "membro `view` pode marcar como lida", ela diz
`request.resource.data.diff(resource.data).affectedKeys().hasOnly(['read'])`, o que
é uma restrição de **conjunto de colunas alteradas**, aplicada a **todos os papéis,
inclusive o dono**. A tabela §4.1 não captura isso. O porte precisa da rule linha a
linha como checklist, não da tabela sozinha.

O template ai9 chega neste ponto no pior estado possível: existe um RBAC de
permissões ligado a planos de cobrança e existe um gate grosseiro `User#og?` /
`#client?` inline em alguns endpoints — mas **nenhum consumidor sistemático**.
Autorização que existe e não é consumida é pior do que autorização ausente, porque
passa a impressão de cobertura. É exatamente o modo de falha da invariante 1
("a autorização é validada no servidor, sempre"): ela não é violada por um bug, é
violada por um endpoint novo que ninguém lembrou de proteger. Esta proposta trata
isso como problema de *processo mecanizado*, não de disciplina.

Depende de `workspace-tenancy` (Workspace, Person, Membership, RLS — D2, D10) e de
`identity-and-auth` (Devise + JWT real, D4). Está na Onda 2 e no caminho crítico:
`commissioning-hierarchy` e `workspace-invitations` só podem declarar policies
depois que o vocabulário de policy existir.

## What Changes

- **Camada de policy objects** em `backend/app/policies/`, no idioma singleton dos
  services do template (`class << self`), sem Pundit (D3 — esta capacidade é a dona
  da decisão). Uma `Authorization::Context` imutável por request carrega
  `user`, `person`, `workspace` e `role`, e é a **única** origem de papel.
- **Matriz §4.1 codificada como dado**, não como `if`s espalhados: as 8 linhas da
  tabela viram 8 *actions* nomeadas em um único arquivo de matriz, e cada policy de
  recurso mapeia suas operações para uma dessas actions.
- **Gate obrigatório no Grape**: um `before` em `Api::Root` que resolve o contexto,
  lê a policy declarada na rota (`route_setting :policy`) e nega antes de qualquer
  service rodar. Rota sem declaração **não responde 200 em ambiente algum** — ela
  levanta em desenvolvimento e falha o CI.
- **Route-sweep spec**: varre `Api::Root.routes` e falha se qualquer endpoint não
  declarar policy ou não constar de uma allowlist pública explícita e versionada.
  Este é o mecanismo que impede a invariante 1 de apodrecer.
- **Suíte executável única das 8 invariantes** (`spec/authorization/invariants/`):
  um arquivo por invariante, nomeado pelo número, cada um provando a invariante
  ponta a ponta via HTTP — não via unit test do policy object. É o contrato de
  aceite do porte inteiro e o lugar onde "as 8 invariantes valem" é verificável de
  uma vez.
- **Varredura negativa de vazamento entre tenants**, endpoint a endpoint, derivada
  da mesma tabela de rotas: para todo endpoint que recebe um id de recurso, um teste
  gerado prova que um membro do workspace B recebe **404** (não 403) ao endereçar um
  recurso do workspace A.
- **Checklist de conformidade linha a linha com `firestore.rules`**: cada `allow`
  do arquivo legado vira uma linha rastreável para o teste do porte que a cobre, ou
  para uma justificativa explícita de divergência.
- **Endurecimentos deliberados sobre o legado**, cada um documentado como divergência:
  (a) notificação só pode ser marcada como lida pelo **destinatário**, coisa que a
  rule legada não checava; (b) a restrição de "só a chave `read` muda" vira **trigger
  de banco**, válida inclusive para o dono; (c) papel deixa de ser inferido de
  `request.auth.uid == wsId` e passa a vir sempre de `memberships.role`.

### Não-objetivos

- **Não** implementa convites (token, e-mail, expiração, consumo atômico) — isso é
  `workspace-invitations`. Aqui só nascem `InvitationPolicy` e os testes de
  invariantes 6 e 7 no plano de **autorização** (quem pode criar/revogar e com que
  escopo de papel). A atomicidade do consumo é da outra capacidade.
- **Não** implementa `audit_logs` nem `notifications` (tabelas, formato de mensagem,
  CHECK de 500 chars, `REVOKE UPDATE, DELETE`) — são de `audit-log` e
  `in-app-notifications`. Aqui declaramos as policies e as provas de invariante 3, 4
  e 8; as constraints são **requisito citado como dependência**, e a suíte de
  invariantes falha se elas não existirem.
- **Não** cria Workspace/Person/Membership nem a RLS (D2/D10) — é `workspace-tenancy`.
- **Não** faz gating de UI. O bloqueio visual (esconder botão para `view`) é
  `app-shell-navigation`; invariante 1 diz explicitamente que ele é conveniência.
- **Não** veda `X-Skip-Auth` — é `seal-template-baseline`. Adicionamos apenas um
  teste de regressão que falha se o furo voltar.
- **Não** cobre revogação de token no logout (D4, denylist) — é `identity-and-auth`.

### BREAKING

- **BREAKING**: todo endpoint Grape existente do template passa a exigir
  `route_setting :policy`. Endpoints herdados que não forem removidos por
  `seal-template-baseline` precisam declarar policy ou entrar na allowlist pública —
  não há default permissivo. O boot em `development` e `test` levanta
  `Authorization::UndeclaredRouteError` na primeira requisição a uma rota sem
  declaração.
- **BREAKING**: o gate `User#og?` / `#client?` inline deixa de ser a fonte de
  decisão. Onde ele sobreviver, vira leitura auxiliar dentro de uma policy.
- **BREAKING**: o RBAC de permissões atrelado a planos de cobrança não participa da
  autorização de domínio do RoboTrack. Papel de workspace e permissão de plano são
  eixos distintos; a matriz §4.1 não consulta plano.

## Capabilities

### New Capabilities

- `authorization-policies`: camada de policy objects, `Authorization::Context`, a
  matriz §4.1 como dado, o gate no Grape, e as regras de negação por recurso
  (projeto/célula/robô/tarefa, avanço, catálogo, log, notificação, membro, workspace).
- `authorization-conformance-suite`: os mecanismos que impedem a autorização de
  apodrecer — route-sweep, suíte executável das 8 invariantes, varredura negativa de
  vazamento entre tenants e checklist de paridade com `firestore.rules`.

### Modified Capabilities

(nenhuma — `openspec/specs/` está vazio; nada foi construído ainda)

### Impact

- **Código novo**: `backend/app/policies/` (base + matriz + ~9 policies),
  `backend/app/lib/authorization/` (contexto, erros, registry de rotas),
  `backend/app/controllers/api/v1/authorization_helpers.rb`,
  `backend/config/authorization/public_routes.yml`.
- **Código alterado**: `backend/app/controllers/api/root.rb` (o `before` ganha a
  etapa de autorização depois da autenticação), `api/v1/base.rb`, e **toda**
  declaração de endpoint (uma linha `route_setting :policy` cada).
- **Banco**: dois triggers e um índice único parcial, todos em migrations desta
  capacidade — `notifications` (só `read`/`read_at` mudam pós-insert),
  `workspaces` (`owner_person_id` imutável), `memberships` (exatamente um `owner`
  por workspace). Não destrutivos.
- **Testes**: `spec/authorization/` novo (sweep + 8 invariantes + cross-tenant +
  paridade). Depende de `spec/factories` e do helper de auth de request criados por
  `seal-template-baseline` — sem eles esta suíte não roda.
- **CI**: `delivery-and-observability` precisa rodar `spec/authorization/` como job
  bloqueante e separado, para que a falha apareça como "autorização" e não diluída
  entre 400 testes.
- **Frontend**: nenhum, além do contrato de erro (403 com `error: "forbidden"`,
  404 para recurso de outro tenant) que `app-shell-navigation` consome.
