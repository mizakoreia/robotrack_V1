# EXECUCAO — seal-template-baseline

Mapa de execução das 31 tarefas de `tasks.md`, quebradas em **grupos coerentes**,
um grupo por invocação. Cada grupo é aplicado, verificado e commitado
isoladamente antes do seguinte começar.

## Critério de agrupamento

O `tasks.md` já codifica coesão por área **e** a ordem de dependência
(design.md §D-E: consumidores antes de produtores). Reagrupar por outro eixo
quebraria essa ordem — remover `Purchase` antes de `AnalyticsService` deixa o
boot quebrado por N commits, sem bisseção possível. Portanto os grupos **adotam
as 8 seções de `tasks.md` como fronteira**, acrescidos de um **G0** não previsto
no plano original (ver abaixo).

A independência entre grupos é *sequencial*, não *paralela*: cada grupo parte de
uma base sã (boot verde + suíte no estado esperado) e entrega outra base sã. Não
são paralelizáveis, e o plano nunca afirmou que fossem.

## G0 — Estabilização da suíte herdada (não previsto em tasks.md)

**Por que existe.** A suíte herdada não estava vermelha: ela **não rodava**.
`config/application.rb` carregava um subconjunto de railties sob `RAILS_ENV=test`
(sem `action_text` e `active_storage`), mas `User` declara `has_rich_text
:biography`. O boot morria, e `config/boot.rb` continha um band-aid
(`autoload_paths.dup` dentro de um `rescue StandardError` vazio) de alguém que
tentou contornar o sintoma. Resultado: `0 examples, 8 errors occurred outside of
examples`.

Sem G0 não há como distinguir o que esta mudança quebrou do que já estava
quebrado — a premissa de todos os "Verificação: `rspec` verde" das tarefas
seguintes.

**Escopo:** `config/application.rb` (carregar `rails/all` em todos os ambientes,
remover o `autoload_paths.dup`, dar defaults aos `ENV.fetch` de SMTP que
levantavam `KeyError`), `config/boot.rb` (remover o band-aid).

**Não** corrige as 6 falhas remanescentes: todas pertencem a specs de módulos que
G3/G4/G6 deletam. Consertá-las seria trabalho jogado fora.

## Mapa de grupos

| Grupo | Área | Tarefas | Depende de |
|---|---|---|---|
| **G0** | Estabilização do boot de teste | — (fora do plano) | — |
| **G1** | Vedação de autenticação HTTP | 1.1, 1.2, 1.3 | G0 |
| **G2** | Vedação do ActionCable e caminho de erro | 2.1, 2.2, 2.3, 2.4 | G1 |
| **G3** | Remoção fase 1 — Cobrança e Asaas | 3.1, 3.2, 3.3 | G2 |
| **G4** | Remoção fase 2 — RBAC por planos | 4.1, 4.2 | G3 |
| **G5** | Remoção fase 3 — Leads, Operations, WhatsApp | 5.1, 5.2, 5.3, 5.4 | G4 |
| **G6** | Remoção fase 4 — Magic-login (D4) | 6.1, 6.2, 6.3, 6.4 | G5 |
| **G7** | Descarte de tabelas, seeds e branding | 7.1, 7.2, 7.3, 7.4, 7.5 | G6 |
| **G8** | Infraestrutura de teste e suítes verdes | 8.1 … 8.6 | G7 |

Total: 31 tarefas em 8 grupos de plano + G0.

## Riscos alocados a grupos específicos

- **G1 — os dois bypasses.** `tasks.md` 1.1 cobre ambos: o header `X-Skip-Auth`
  *e* o fallback `ClientApplication.active.find_by(token:)`, que autentica um
  portador de token opaco sem usuário, sem escopo e sem expiração (design §D-B).
  Tratar só o header deixaria a porta dos fundos aberta.
- **G1 — quebra do frontend.** `frontend/src/lib/api/client.ts` emite
  `X-Skip-Auth: 1` em `getPublic`/`postPublic` (linhas 118 e 129) e o
  interceptor de request usa o mesmo header como marcador para não anexar
  `Authorization` (linha 35). Remover o bypass no backend sem tocar aqui deixa o
  front mandando um header inerte. O refator entra **no mesmo grupo**: substituir
  o header de rede por um marcador interno que não trafega, preservando a
  semântica "esta chamada não leva token".
- **G7 — único grupo destrutivo em dados.** Começa por 7.1 (dump `pg_dump -Fc`
  **restaurado** num banco descartável). Dump não restaurado não conta como
  backup (design §D-F).

## Comando por grupo

O CLI `openspec` não está instalado como binário global, mas está disponível via
npx com versão fixada:

```bash
npx --yes @fission-ai/openspec@1.6.0 <subcomando>
```

Comandos de apoio usados a cada grupo:

```bash
# antes de começar o grupo — confirma schema, artefatos e o que falta
npx --yes @fission-ai/openspec@1.6.0 status       --change seal-template-baseline --json
npx --yes @fission-ai/openspec@1.6.0 instructions apply --change seal-template-baseline --json

# depois de marcar as tarefas do grupo — o plano tem de continuar coerente
npx --yes @fission-ai/openspec@1.6.0 validate --changes --strict
```

Invocação por grupo (o escopo é a fatia de `tasks.md` que o grupo cobre):

```
/opsx:apply seal-template-baseline   → escopo: G0   (estabilizar boot de teste)
/opsx:apply seal-template-baseline   → escopo: G1   (tarefas 1.1–1.3)
/opsx:apply seal-template-baseline   → escopo: G2   (tarefas 2.1–2.4)
/opsx:apply seal-template-baseline   → escopo: G3   (tarefas 3.1–3.3)
/opsx:apply seal-template-baseline   → escopo: G4   (tarefas 4.1–4.2)
/opsx:apply seal-template-baseline   → escopo: G5   (tarefas 5.1–5.4)
/opsx:apply seal-template-baseline   → escopo: G6   (tarefas 6.1–6.4)
/opsx:apply seal-template-baseline   → escopo: G7   (tarefas 7.1–7.5)
/opsx:apply seal-template-baseline   → escopo: G8   (tarefas 8.1–8.6)
```

`instructions apply` devolve a lista de tarefas com status mas **não** tem noção
de "grupo" — o agrupamento é desta execução, registrado neste arquivo. O CLI é a
fonte da verdade sobre artefatos, progresso e validação; o recorte em G0..G8 é a
camada por cima.

## Protocolo por grupo

1. Aplicar as tarefas do grupo.
2. `bundle exec rspec` (backend) e `npx vitest run` (frontend), comparando com o
   estado esperado registrado abaixo — não com "verde", que só é exigível ao fim
   de G8.
3. Marcar `- [ ]` → `- [x]` em `tasks.md` para as tarefas do grupo.
4. Commit local descrevendo o grupo. Nenhum `push` (sem credencial configurada).
5. Conferir que nenhum `.env` entrou no commit (`backend/.env` e `frontend/.env`
   existem e estão cobertos por `.gitignore:14`, `**/*.env`).

## Estado da suíte

**Ambiente:** Ruby 3.2.3 via rbenv — as shims não estão no `PATH` padrão do shell
não-interativo; todo comando de backend precisa de
`export PATH="$HOME/.rbenv/shims:$PATH"`. Frontend usa pnpm via `npx`.

| Momento | Backend (rspec) | Frontend (vitest) |
|---|---|---|
| Herdado (antes de G0) | **0 exemplos, 8 erros de carga** — não bootava | 10 arquivos: 6 falhos / 4 ok; 12 testes: 3 falhos / 9 ok |
| Após G0 | 24 exemplos, 6 falhas | inalterado |
| Alvo ao fim de G8 | 0 falhas | 0 falhas, 0 erros de importação |

As 6 falhas pós-G0, todas em specs de módulos a remover:

- `pre_register_flow_spec.rb` (2) — magic-login → sai em G6/G8
- `auth/checkout_session_service_spec.rb` (3) — cobrança → sai em G3/G8
- `permissions_sync_service_spec.rb` (1) — `uninitialized constant PlanFeature`,
  RBAC por planos → sai em G4/G8

## Dívidas registradas por changes posteriores

- **`paper_trail` (gem não usada) — recomendação de REMOÇÃO do Gemfile**
  (registrado por `audit-log` 9.1, parecer da Decisão 8). A gem está no Gemfile
  (`gem 'paper_trail'`, 17.0.0) e não é usada em lugar nenhum. `audit-log` a
  avaliou e REJEITOU para o log de auditoria de domínio, por quatro razões
  independentes: (1) semântica errada — grava diffs por registro, não a narrativa
  de evento de negócio em pt-BR de §2.8; (2) a tabela `versions` é MUTÁVEL por
  design (a API pública tem `destroy_all`, `limit` de poda, `reify`/rollback) —
  incompatível com a invariante 3 (append-only para todos, inclusive o dono);
  (3) sem tenancy (`versions` não tem `workspace_id`, a gem não conhece RLS →
  2ª superfície de vazamento, contra D2); (4) volume desproporcional. Log de
  auditoria de domínio ≠ versionamento de registro. Ação: remover do Gemfile a
  menos que outra capacidade a reivindique.
