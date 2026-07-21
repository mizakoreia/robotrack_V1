# EXECUCAO — authorization-policies

Mapa de execução das 28 tarefas de `tasks.md`, quebradas em **grupos coerentes**,
um grupo por invocação. Cada grupo é aplicado, verificado e commitado
isoladamente antes do seguinte começar. Mesmo método de
`seal-template-baseline`, `workspace-tenancy`, `identity-and-auth` e
`workspace-invitations` (ver os `EXECUCAO.md` respectivos).

Este arquivo é escrito **antes** de qualquer código, de propósito. Se a sessão
cair, o próximo agente retoma pela seção **RETOMADA** no fim.

## Ponto de partida

- Branch: `authorization-policies`, criada de `main` (`48497fd`, tip de
  `workspace-invitations` — a main JÁ contém as 4 ondas anteriores). **Sem push.**
- **Ambiente NOVO**: WSL Ubuntu 24.04 nesta máquina (as ondas anteriores rodaram
  em outra). Provisionado nesta sessão: ruby 3.2.3 (apt), Postgres 16,
  `robotrack_user` (superuser local) + `db/roles.sql` aplicado em
  `robotrack_dev` e `robotrack_test`, Node 22 + **pnpm** (o lockfile real do
  frontend é `pnpm-lock.yaml`; o `package-lock.json` está dessincronizado).
- Baseline medida em 21/07/2026, backend como `robotrack_app`:
  **backend 318 exemplos / 0 falhas**, **frontend 63 / 0**, `tsc --noEmit` limpo.
- Papéis de banco valendo: runtime (inclusive rspec) conecta como
  `robotrack_app` (sem SUPERUSER/BYPASSRLS); migrations como
  `robotrack_migrator`. Ver `backend/db/PROVISIONING.md`.
- Piso de policies de `workspace-invitations` existe e será **absorvido**:
  `app/policies/{application,invitation,membership}_policy.rb` (instância,
  `role:` kwarg), declarações `route_setting :policy, 'Classe#metodo?'` (string)
  e `spec/requests/policy_route_sweep_spec.rb` (superfície convite/equipe).

## O objetivo central desta change

A invariante 1 da §4.1 — "a autorização é validada no servidor, sempre" — como
**processo mecanizado**, não disciplina: matriz §4.1 como dado num arquivo,
decisão única por request no `before` do Grape, rota sem policy que NÃO
responde 200 em ambiente algum, e uma suíte de conformidade que impede tudo
isso de apodrecer (route-sweep, 8 invariantes executáveis, varredura
cross-tenant, paridade com `firestore.rules`).

## Critério de agrupamento

`tasks.md` tem 6 seções e a ordem de dependência é 1:1 com elas. Única
correção: G3 e G4 dependem ambos só de G2 — executo G3 antes por ser menor e
porque G5 (inv_5) precisa dos triggers de G3.

| Grupo | Área | Tarefas | Depende de |
|---|---|---|---|
| **G0** | Este mapa | — | baseline |
| **G1** | Núcleo: matriz, contexto, BasePolicy, 12 policies, spec literal | 1.1–1.6 | baseline |
| **G2** | Gate no Grape: helpers, before + AUTHZ_ENFORCE, fail-closed, rescue_from, public_routes.yml, declaração em TODOS os endpoints, X-Skip-Auth | 2.1–2.7 | G1 |
| **G3** | Invariantes no banco: 2 triggers + índice único parcial + specs SQL cru | 3.1–3.5 | G2 |
| **G4** | Cross-tenant: lookup 404, gerador + overrides, RLS-sozinha, X-Total-Count | 4.1–4.4 | G2 |
| **G5** | Conformidade: route-sweep, invariants/ (8+meta), matriz papel×ação, legacy_parity | 5.1–5.7 | G3, G4 |
| **G6** | Fechamento: cop anti `role ==`, job CI, remoção da flag, relatório | 6.1–6.4 | G5 |

Total: 28 tarefas em 6 grupos de trabalho. Sequencial, sem paralelismo.

## Decisões de desenho já fixadas pela change (não reabrir)

- **D3.1** policies singleton (`class << self`), sem Pundit.
- **D3.2** matriz §4.1 é DADO: 8 actions num único arquivo, frozen; nenhuma
  policy compara papel.
- **D3.3** `Authorization::Context` imutável, papel SÓ de `memberships`.
- **D3.4** declaração por rota + fail-closed (levanta em dev/test, 500 em prod).
- **D3.5** route-sweep em CI; allowlist pública YAML com `reason` obrigatório e
  detecção de órfã.
- **D3.6** recurso de outro tenant = 404 indistinguível de inexistente; 403 só
  para recurso do próprio workspace com papel insuficiente.
- **D3.7** inv. 4: trigger de colunas (`read`, `read_at`, `updated_at`) para
  TODOS os papéis + `mark_read?` checa destinatário (divergência D-A).
- **D3.8** inv. 5: trigger `owner_person_id` + índice único parcial 1-owner;
  sem action de transferência (divergência D-B).
- **D3.9** `AuditLogPolicy` sem verbo de escrita (`respond_to?(:update?)` false).
- **D3.10** cross-tenant GERADO da tabela de rotas; rota sem gerador e sem
  override falha.
- **D3.11** paridade: uma entrada YAML por `allow` do legado, `covered_by` ou
  `divergence` obrigatório, contagem conferida.
- **D3.12** contrato de erro: corpo de chave única `error`, sem nome de
  policy/action/papel.

## Decisões que EU tomo aqui (não estavam resolvidas na change)

1. **Absorção do piso.** As 3 policies de instância viram singletons D3.1 e as
   declarações string viram a forma nova. O `policy_route_sweep_spec.rb` é
   substituído por `spec/authorization/route_sweep_spec.rb` cobrindo a
   superfície INTEIRA — a varredura só cresce (de ~6 rotas para todas), nunca
   encolhe. A troca de forma acontece TODA dentro do G2, para nunca haver
   commit com duas formas convivendo.
2. **Rotas autenticadas SEM tenant** (índice de workspaces, PATCH de workspace,
   aceite por token, e a superfície global OG de `users`/`uploads`/`downloads`):
   a matriz §4.1 pressupõe papel de workspace, que essas rotas não têm no
   header. A declaração ganha duas formas explícitas:
   `route_setting :policy, { policy:, action: }` para rota de domínio
   (avaliada pelo gate contra o contexto) e
   `route_setting :policy, { access: :authenticated }` para rota autenticada
   isenta de tenant — a autorização fina dessas rotas continua onde está
   (ownership resolvido no serviço; `require_og!` nos endpoints do template),
   e o sweep exige que TODA rota declare uma das duas formas ou esteja na
   allowlist pública. Nada fica sem declaração; nenhum default permissivo.
   `PATCH /workspaces/:id` também ganha guarda de matriz dentro do fluxo
   (action `manage_catalog` via papel resolvido) — ver design.md "Perguntas em
   aberto" 2.
3. **`notifications` não existe** (`in-app-notifications` não entregue). A
   migration 3.3 é no-op registrada (prevista no design); a metade HTTP da
   inv. 4 fica `pending` nomeando `in-app-notifications`; a metade policy
   (`NotificationPolicy.mark_read?` checa destinatário) é implementada e
   testada em nível de policy. `tasks.md` 5.3 lista inv_4 entre as "fechadas
   aqui" — o estado real diverge e fica REGISTRADO aqui, não escondido.
4. **inv_6/inv_7 já têm provas reais** (suíte de invariantes 6 e 7 de
   `workspace-invitations`, G6 daquela onda). Os arquivos `inv_6_*`/`inv_7_*`
   fazem a prova de AUTORIZAÇÃO (quem cria/revoga, escopo de papel) e citam a
   suíte existente para a atomicidade — sem duplicar.
5. **`firestore.rules` é referência EXTERNA de leitura.** Regra do usuário
   desta sessão: nada do repositório legado entra no robotrack_V1; o porte é
   criado do zero. `legacy_parity.yml` é escrito à mão, uma entrada por
   `allow` (path, verbo, linha — 22 no total, contadas na leitura), e o spec
   confere a contagem contra uma constante local `EXPECTED_ALLOWS = 22`
   documentada com o commit legado de referência (`mizakoreia/RoboTrack@50c7a2f`),
   em vez de ler o arquivo do outro repo em runtime.
6. **Matriz papel×ação (5.5) em duas camadas.** A maior parte das 8 linhas não
   tem endpoint ainda (comissionamento, avanço, catálogo, log são de ondas
   futuras). Camada 1: unit spec completo 3 papéis × 8 actions contra
   `PermissionMatrix` (sempre roda). Camada 2: request specs para as linhas
   com endpoint real hoje (`read_workspace` via memberships/workspaces,
   `manage_membership` via invitations/memberships) com os negativos de Bruno
   e Clara. As linhas sem endpoint entram no arquivo com `pending` nomeando a
   capacidade que trará a rota — mesmo padrão da decisão 3.
7. **`AUTHZ_ENFORCE` nasce e morre nesta change** (2.2 cria, 6.3 remove). A
   flag existe para o rollout endpoint-a-endpoint DENTRO do G2 ser committável;
   como o G2 termina com todas as rotas declaradas, o G6 a remove sem fase
   intermediária entre changes.

8. **O esquema real da Onda 1 difere do design desta change — e é mais forte.**
   O design assume dono-como-membership (`role='owner'` no enum, índice único
   parcial, coluna `owner_person_id`). O que existe: dono é a coluna
   `workspaces.owner_user_id`, imutável pelo trigger `workspaces_owner_immutable`
   (JÁ existe desde a Onda 1) + REVOKE de coluna em `roles.sql`; o trigger
   `memberships_owner_is_not_member` impede o dono de virar linha de membership;
   o enum `membership_role` é só `('edit','view')`. "Exatamente um dono" vale
   por construção (coluna NOT NULL), sem índice parcial. Adaptação: 3.1 e 3.2
   viram VERIFICAÇÃO (specs por SQL cru dos mecanismos existentes, adicionados
   se faltarem), não migrations novas; `Authorization::Context` resolve papel à
   moda da Onda 1 (dono pela coluna, senão `memberships.role`), e a inv. 2
   continua valendo: papel resolvido no servidor, nunca de claim/índice de UI.

## Armadilhas previstas

1. **O `rescue_from :all` de `Api::Root` engole tudo.** As exceções de
   autorização precisam de `rescue_from Authorization::Forbidden/NotFound/
   UndeclaredRouteError` ESPECÍFICOS, declarados no mesmo `Api::Root` — Grape
   resolve por classe mais específica, mas o handler genérico loga como
   `api_error` 500; conferir status e corpo nos specs de contrato (2.4).
2. **`env['api.endpoint'].route_setting(:policy)`** — o `before` roda no
   contexto do endpoint; `route_setting` é lido do endpoint corrente via
   `self.route_setting` NÃO existe em runtime de request; a leitura é
   `env['api.endpoint'].options[:route_options][:settings]` ou
   `route.settings` — verificar a API real do Grape instalado ANTES de
   escrever o helper (o sweep atual usa `route.settings[:policy]` em specs;
   runtime é outro caminho).
3. **As varreduras existentes asseram conteúdo exato.**
   `auth_route_sweep_spec` (PUBLIC_ROUTES, 6 entradas) e
   `tenant_route_sweep_spec` (isenções cientes de método) continuam valendo.
   O G2 NÃO mexe em `PUBLIC_ROUTES`/`TENANT_EXEMPT_ROUTES`; a
   `public_routes.yml` nova é a MESMA lista pública em formato auditável — o
   sweep novo confere a equivalência entre as duas em vez de criar segunda
   fonte de verdade divergente.
4. **`tenancy_probe` só monta em `test`** — `Api::Root.routes.size` difere
   entre ambientes. Sweep e contagens rodam em `test`; nenhuma asserção de
   tamanho absoluto duro no código de produção.
5. **Swagger (`GET /swagger_doc`, `/swagger_doc/:name`) são rotas Grape** —
   entram na allowlist pública com `reason`.
6. **Trigger em tabela com RLS FORÇADA**: as funções de trigger de 3.1/3.3
   rodam com o papel corrente; nada de `SECURITY DEFINER` (não precisam ler
   outras linhas). O spec de 3.5 roda por SQL cru como `robotrack_app` E
   confere que nem o dono da tabela escapa (conexão do migrator).
7. **`workspaces` já tem REVOKE de coluna** (`roles.sql`: app só atualiza
   `name`, `updated_at`). O trigger de 3.1 é a SEGUNDA camada (cobre
   migrator/admin); o spec de inv_5 pela API espera `422 unpermitted_parameters`
   que o endpoint atual já dá — não regredir para silêncio.
8. **Specs que desligam a policy (4.3)** precisam religar SEMPRE
   (`around` + `ensure`) — senão um exemplo envenena a suíte inteira.
9. **`db:schema:load`/`structure.sql` omite GRANT/REVOKE** (`pg_dump -x`) —
   qualquer REVOKE novo mora em `roles.sql` reaplicável, não só na migration.
   Nesta change não há REVOKE novo previsto; conferir ao final.
10. **Ambiente novo**: extensões `citext`/`pgcrypto` pertencem ao
    `robotrack_migrator` aqui (recriadas por ele — PG16 as tem como trusted).
    `COMMENT ON EXTENSION` do structure.sql falha se a extensão pertencer a
    outro papel; não "consertar" isso com superuser no fluxo normal.

## Decisões de ambiente (novas desta máquina, sem regressão das regras)

```bash
# migrations (como migrator), depois suíte (como app) — PROVISIONING.md
cd ~/robotrack_V1/backend
MIG_DEV="postgres://robotrack_migrator:mig_dev_pw@localhost/robotrack_dev"
MIG_TEST="postgres://robotrack_migrator:mig_dev_pw@localhost/robotrack_test"
RAILS_ENV=development DATABASE_URL=$MIG_DEV  bundle exec rails db:migrate
RAILS_ENV=test        DATABASE_URL=$MIG_TEST bundle exec rails db:migrate
bundle exec rspec

# frontend: pnpm (não npm ci — package-lock.json dessincronizado)
cd ~/robotrack_V1/frontend
./node_modules/.bin/vitest run && ./node_modules/.bin/tsc --noEmit
```

Gems em `vendor/bundle` (`bundle config set --local path vendor/bundle`).
Postgres e Redis são serviços do WSL (`service postgresql start`). Sem push —
credencial não configurada nesta máquina; os commits são locais como nas ondas
anteriores.

## Protocolo por grupo

1. Aplicar as tarefas do grupo (migrations como `migrator`, código, specs).
2. `bundle exec rspec`; front não muda nesta change, mas o fechamento (G6)
   roda `vitest` + `tsc` uma vez para provar não-regressão.
3. Marcar `- [ ]` → `- [x]` em `tasks.md`.
4. `npx --yes @fission-ai/openspec@1.6.0 validate authorization-policies --strict`.
5. Commit local com prefixo `G<n>:`. Nenhum push.
6. Conferir que nenhum `.env`/`database.yml` real e nenhum `coverage/` entrou.

## Estado esperado da suíte por grupo

| Após | Backend (rspec, como `robotrack_app`) |
|---|---|
| Baseline | 318 / 0 |
| G1 | + specs de matriz/contexto/policies verdes |
| G2 | + specs de gate, contrato de erro e X-Skip-Auth; sweep antigo substituído |
| G3 | + specs DDL (SQL cru) dos 2 triggers + índice |
| G4 | + varredura cross-tenant gerada + RLS-sozinha + X-Total-Count |
| G5 | + route-sweep total, 8 invariantes (4 reais, 4 pending com motivo), paridade 22/22 |
| G6 | grep `AUTHZ_ENFORCE` = 0 fora deste arquivo/CHANGELOG; relatório 6.4 |
| Alvo final | 0 falhas; frontend 63 / 0 e `tsc` limpo (inalterados) |

## Comandos de CLI de apoio

```bash
npx --yes @fission-ai/openspec@1.6.0 validate authorization-policies --strict
npx --yes @fission-ai/openspec@1.6.0 show     authorization-policies --json --deltas-only
```

## Progresso

- [x] G1 — Núcleo (1.1–1.6) — backend 318 → 346
- [x] G2 — Gate no Grape (2.1–2.7) — backend 346 → 353
- [ ] G3 — Invariantes no banco (3.1–3.5)
- [ ] G4 — Cross-tenant (4.1–4.4)
- [ ] G5 — Conformidade (5.1–5.7)
- [ ] G6 — Fechamento (6.1–6.4)

## RETOMADA

**Se a sessão caiu, comece por aqui.**

1. `git log --oneline -8` na branch `authorization-policies`. Cada grupo é UM
   commit com prefixo `G<n>:`; o próximo grupo é o seguinte da tabela acima.
2. `tasks.md` tem o estado fino (`- [x]` = feito E verificado). `- [x]` sem
   commit correspondente = sessão caiu no meio; rode `git status` e a suíte
   antes de confiar.
3. Rode a baseline do ponto em que está ANTES de escrever código (bloco
   **Decisões de ambiente** acima). Migration pendente = rodar como
   `robotrack_migrator` primeiro.
4. Releia **Decisões que EU tomo aqui** e **Armadilhas previstas** — em
   especial a 2 (leitura de `route_setting` em runtime) e a 3 (varreduras
   existentes com conteúdo exato).
5. Regras invioláveis: **sem push**, nenhum `.env` real em commit, runtime sem
   SUPERUSER/BYPASSRLS, RLS forçada, varreduras não-vácuas e só crescendo,
   vazamento entre tenants = 404.
6. Quando os seis grupos estiverem `- [x]`: atualizar **Progresso**, escrever
   **CONCLUSÃO** (tabela antes/depois, garantias conferidas, pendências para
   outras changes) e **parar**.
