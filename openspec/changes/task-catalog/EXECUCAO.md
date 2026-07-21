# EXECUCAO — task-catalog

Mapa de execução das 34 tarefas de `tasks.md`, em grupos coerentes, um commit
por grupo. Mesmo método das seis changes anteriores.

Escrito ANTES de qualquer código. Sessão caiu → **RETOMADA** no fim.

## Ponto de partida

- Branch: `task-catalog`, criada de `commissioning-hierarchy` (`b75b072`).
  **Sem push.**
- Baseline: **backend 604 / 0 (12 pending)**, **frontend 75 / 0**, `tsc` limpo.
- Ambiente WSL desta máquina — ver EXECUCAO de `authorization-policies`.
- `commissioning-hierarchy` ENTREGUE: `projects`/`cells`/`robots` com
  `workspace_id`, RLS forçada, `UNIQUE (id, workspace_id)` e
  `robots.application` já restrito aos 6 literais da §1.2.
- `TaskTemplatePolicy` JÁ EXISTE (singleton, do G1 de `authorization-policies`,
  mapeando §4.1: leitura para os 3 papéis, escrita `owner`/`edit`). A tarefa
  4.1 vira verificação + o predicado `sync?`.

## O objetivo central desta change

O catálogo é a **fonte de toda tarefa que existe no sistema**: nenhum robô
nasce com tarefas próprias — nasce com uma cópia do catálogo do workspace,
filtrada pela Aplicação (§2.5). Sem ele, `robot-tasks` não tem o que copiar e
`progress-rollup` não tem denominador.

## Ordem dos grupos (a seção 5 foi movida para o FIM, e por quê)

`tasks.md` tem 6 seções, mas a **5 (sincronização retroativa) depende da tabela
`tasks`**, que é de `robot-tasks`. Interdependência real entre as duas changes:
robot-tasks/§5 precisa de `task_templates`; task-catalog/§5 precisa de `tasks`.
Resolução: esta change entrega tudo que NÃO depende de `tasks`, e o grupo da
sincronização fica por último, executado **depois** de `robot-tasks` (o usuário
autorizou task-catalog primeiro justamente para desbloquear aquela).

| Grupo | Área | Tarefas | Depende |
|---|---|---|---|
| **G0** | Este mapa | — | baseline |
| **G1** | Esquema: `task_templates`, CHECK de domínio, índices, RLS, spec por SQL cru | 1.1–1.7 | baseline |
| **G2** | Model, normalização de `app_filters`, `ApplicabilityFilter` (Ruby + SQL) | 2.1–2.4 | G1 |
| **G3** | Catálogo padrão (31 itens), seed no bootstrap, ordenação e isolamento | 3.1–3.6 | G2 |
| **G4** | Policy, entity, endpoints CRUD + metadados, specs negativos | 4.1–4.6 | G3 |
| **G5** | Cliente: endpoints, hooks, tipo derivado do backend | 6.1–6.4 | G4 |
| **G6** | Sincronização retroativa (§2.6) | 5.1–5.7 | G5 **+ robot-tasks** |

Total: 34 tarefas em 6 grupos.

## Decisões de desenho já fixadas (não reabrir)

- **D-TC-1** o prefixo de ordenação (`A. `, `B. `…) fica DENTRO de `cat`.
- **D-TC-2** sentinelas resolvidas por normalização na ESCRITA, tolerância na
  leitura: `[]`, `Misto / Geral` e `Todas` colapsam para `[]`.
- **D-TC-4** seed é hook do bootstrap de workspace, na MESMA transação; dados
  num arquivo único; teste que trava os números.
- **D-TC-5** `apps` (nome legado) só na fronteira da API; `appFilters` vence em
  conflito, com warning estruturado; nada abaixo do endpoint conhece `apps`.
- **D-TC-6** sync dedup por `lower(btrim(desc))`, escopo do robô, transação
  única, `insert_all` só das faltantes (nunca upsert — zeraria progresso).
- **D-TC-7** isolamento por RLS + policy; template de outro workspace = 404.

## Decisões que EU tomo aqui

1. **`robots.application` continua `text` + CHECK — o enum `robot_application`
   NÃO é criado** (tarefas 1.1/1.3, D-TC-3). Motivo: `commissioning-hierarchy`
   JÁ entregou a coluna com CHECK dos 6 literais, por decisão explícita
   (D-H10: "adicionar valor a um enum Postgres não é reversível dentro de uma
   migration transacional; CHECK é alterável por DROP/ADD CONSTRAINT"). As
   duas changes concordam na INVARIANTE — o banco rejeita valor fora da lista,
   que é o que D-TC-3 exige contra `varchar` solto — e divergem só no
   mecanismo. Converter agora seria migration destrutiva (a própria tarefa 1.2
   pede backup por isso) para trocar uma constraint que já funciona por outra
   menos reversível. O endpoint `GET /api/v1/meta/robot_applications` (4.5)
   serve `Robot::APPLICATIONS` — fonte única no model — com o MESMO contrato:
   6 itens, na ordem da §1.2, sem `"Todas"`. 1.2 (backup) fica sem efeito.
2. **Divergência interna da change, resolvida com evidência:** `design.md`
   D-TC-4 diz "exatamente **3** com `app_filters` não vazio"; `tasks.md` 3.1
   diz **2** e NOMEIA os dois (`Calibração de Cola` → `["Sealing"]`,
   `Check sinais de Gripper` → `["Handling","Solda Ponto"]`). A leitura do
   catálogo legado (`src/model/data.js` de `mizakoreia/RoboTrack@50c7a2f`,
   referência externa) confirma: 31 itens, 9 categorias, `weight: 1` em todos,
   **2** com filtro. Vale o `tasks.md`; o `3` do design é erro de redação.
3. **O catálogo é transcrito do legado como DADO de referência**, não copiado
   como arquivo (regra do usuário): o array Ruby é escrito do zero, com os
   mesmos 31 `cat`/`desc` — inclusive as grafias com erro do original
   (`"Traj, de Descarte"`, `"Otimização de Trajetoria"`, `"Dryrun Baixa
   velocidade ate 100%"`), porque §1.4 item 3 exige que o importador case por
   `desc` e qualquer "correção" ortográfica aqui duplicaria a tarefa na
   importação. Registrado para `legacy-data-migration`.
4. **Seed no bootstrap** (3.4): `Workspaces::BootstrapService` é da Onda 1 e
   tem spec próprio; a chamada entra DENTRO da transação existente, e o spec
   de falha injetada prova que nenhum workspace nasce sem catálogo.
5. **Grupo 6 (sync) provavelmente fecha depois de `robot-tasks`** — se ao
   chegar nele a tabela `tasks` não existir, ele NÃO é implementado pela
   metade: as tarefas 5.x ficam `- [ ]` com nota, e a CONCLUSÃO registra a
   change como "5 de 6 grupos". Nada de spec `pending` fingindo cobertura de
   um service que não existe.

## Armadilhas previstas

1. **`desc` é palavra reservada do SQL** (`ORDER BY ... DESC`). A coluna
   precisa de aspas em SQL cru (`"desc"`), e no ActiveRecord `Task#desc`
   colide com nada, mas `select(:desc)` gera SQL válido só com quoting — usar
   sempre o quoting do adapter.
2. **`ORDER BY cat COLLATE "C"`** (3.5): sem a collation explícita a ordem de
   `A. Hardware`…`I. Aceitação` muda entre `lc_collate` `pt_BR.UTF-8` e `C`.
   O banco desta máquina é `C.UTF-8` — o spec tem de testar as duas.
3. **`insert_all` pula callbacks E `default_scope`**: o `workspace_id` precisa
   ir explícito em cada hash, senão a RLS rejeita (mesmo modo de falha que
   D-RT-5 antecipa para `robot-tasks`).
4. **Índice único `(workspace_id, lower(btrim(desc)))`** faz o seed falhar se
   o catálogo tiver duas descrições iguais normalizadas — os 31 são distintos,
   mas o spec de trava precisa afirmar isso.
5. **`app_filters text[]` com CHECK `<@ ARRAY[...]`**: `'{}'::text[] <@ ...` é
   TRUE (conjunto vazio é subconjunto de tudo), então o CHECK não impede o
   caso normalizado.
6. **A entity expõe `appFilters` (camelCase)** — divergente do resto da API,
   que é snake_case. É o que a tarefa 4.2 pede (o cliente legado espera assim);
   manter e documentar.
7. **route-sweep e cross-tenant crescem junto** (mesma regra das duas changes
   anteriores): as rotas novas declaram policy e entram no GERADORES no MESMO
   grupo.

## Protocolo por grupo

1. Aplicar tarefas (migrations como `robotrack_migrator`, dev E test).
2. `bundle exec rspec`; G5 também `vitest run` + `tsc --noEmit`.
3. Marcar `- [x]` em `tasks.md`.
4. `npx --yes @fission-ai/openspec@1.6.0 validate task-catalog --strict`.
5. Commit `G<n>:`. Sem push, sem `.env`/coverage.

## Progresso

- [x] G1 — Esquema (1.1–1.7; 1.1–1.3 nao aplicadas, decisao 1) — backend 604 → 617
- [x] G2 — Model e filtro de aplicabilidade (2.1–2.4) — backend 617 → 652
- [ ] G3 — Catálogo padrão e seed (3.1–3.6)
- [ ] G4 — Policy e API (4.1–4.6)
- [ ] G5 — Cliente (6.1–6.4)
- [ ] G6 — Sincronização retroativa (5.1–5.7) — depende de `robot-tasks`

## RETOMADA

1. `git log --oneline -8` na branch `task-catalog`; um commit por grupo.
2. `tasks.md` tem o estado fino.
3. Baseline antes de codar (migrations como `robotrack_migrator`, rspec, vitest).
4. Reler **Decisões que EU tomo** (em especial 1: NÃO criar o enum) e
   **Armadilhas** (1: `desc` reservada; 2: collation).
5. Invioláveis: sem push, sem `.env` em commit, runtime sem SUPERUSER/BYPASSRLS,
   RLS forçada na tabela nova, varreduras só crescem, cross-tenant = 404.
6. G6 só quando `robot-tasks` existir; senão, CONCLUSÃO parcial honesta.
