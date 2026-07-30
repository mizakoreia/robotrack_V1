# EXECUCAO — internationalization (G0 = planejamento)

Mapa de execução escrito ANTES de qualquer código (commit G0). App em EN além do
pt-BR, com seletor por bandeira (BR/GB). **NADA foi traduzido nem aplicado:** sem
migração, sem push, sem tocar em servidor/túnel. Os arquivos de túnel da demo
(`frontend/vite.config.ts`, `frontend/src/lib/api/client.ts`) seguem **sem commit**.

## Skills aplicadas (pedido do dono)

- **impeccable** — carregada (register `product`: `reference/product.md` +
  PRODUCT.md/DESIGN.md via `context.mjs`). Aplicada ao desenho do seletor (D-I7):
  controle ≠ badge, `PortalMenu` com dois alvos explícitos (não toggle que cicla),
  bandeira SVG não-emoji `aria-hidden` com o idioma como nome acessível, alvo ≥40px de
  luva, texto visível para legibilidade de galpão, contraste AA nos dois temas.
- **caveman** — aplicada ao chat (saída tersa), NÃO aos artefatos versionados (este
  arquivo, proposal/design/specs/tasks e o `GLOSSARIO.md` seguem bem-formados).

## RECONCILIAÇÃO COM A REALIDADE (crítico — ler antes de codar)

### Frontend
- **Sem framework de i18n, sem locale.** `lib/i18n/*` = 11 módulos pt-BR planos
  (~337 chaves; ~300 folhas + 41 funções que embutem gramática pt: artigos
  `do`/`pelo`/`pela`, plural `n===1?`). `<html lang="pt-BR">` fixo (`index.html:2`).
- **~82% dos arquivos de UI NÃO usam `lib/i18n`** (25/138 importam). Inline pesado:
  `app/AppShell.tsx` (itens de menu, aria do topbar/nav), `features/auth/AuthPage.tsx`
  (login inteiro), `app/pages/AjudaPage.tsx` (476 linhas de prosa), Visão Geral/
  hierarquia, `components/charts/*`, `components/StorageWarning.tsx`.
- **Sweeps que o EN precisa não quebrar:** `convention-sweep.test.ts` **regra G**
  parseia `lib/i18n` com regex `^\s{2,}([A-Za-z]\w*):\s*(['"])(.+?)\2` — **assume
  literal plano de uma linha**. `src/lib/i18n/__tests__/invitations.i18n.test.ts` e
  `feedback.i18n.test.ts` casam **frase pt-BR literal ≥30 chars**;
  `components/progress/__tests__/progress-label.test.tsx` e
  `features/report/__tests__/literalSweep.test.ts` idem. `frontend/tests/no-emoji.test.ts`
  reprova emoji (inclui bandeiras regional-indicator). → **Mudar a forma do módulo e
  atualizar esses parsers é a MESMA tarefa (G1.2/1.3).**
- **Formatação:** 6 call-sites fixam `'pt-BR'` em `Intl`/`toLocaleString`/
  `localeCompare` (`report/format.ts`, `feedback/FeedbackInbox.tsx`,
  `robot-tasks/HistoryModal.tsx`, `robot-tasks/AssignmentModal.tsx`,
  `settings/CatalogPanel.tsx`, `kpi/PerformanceIndicators.tsx`). Sem lib de data; sem
  RTL (EN é LTR).
- **Storage/tema = molde do seletor.** `store/themeStore.ts` (Zustand+`persist` →
  `localStorage['rt-theme']` via `zustandStorage('local')`, default `dark`) aplicado
  por `hooks/useTheme.ts`; `lib/safeStorage.ts` dá o fallback de memória. `useLanguageStore`
  → `localStorage['rt-lang']`, default `pt-BR`. `SendFeedbackDialog.tsx:51` já lê
  `navigator.language` (sinal de default de 1ª visita — mas o dono quer pt-BR fixo).
- **Casa do seletor:** array de itens do menu da conta em `AppShell.tsx` (ao lado de
  "Alternar tema"); `features/settings/AppearancePanel.tsx`; `features/auth/AuthPage.tsx`.

### Backend
- **rails-i18n já declara** `default_locale = :'pt-BR'`, `available_locales = %i[pt-BR en]`,
  `fallbacks = { 'pt-BR' => [:en] }` (`config/application.rb`). **Mas não há um único
  `en.*.yml`** e `raise_on_missing_translations = true` (dev/test) → qualquer caminho
  sob `:en` **quebra hoje**. Sem `Accept-Language`, sem coluna `locale`, sem
  `I18n.with_locale` por requisição. 10 arquivos `config/locales/pt-BR.*.yml`.
- **Notificações — CONGELADAS por destinatário no INSERT.**
  `services/notifications/message_builder.rb:11` `LOCALE = :'pt-BR'` fixo; `:32`
  `I18n.t(key, locale: :'pt-BR', **vars)`. `create_service.rb:155` grava
  `msg:` + `ts_local:` na linha. Trigger `notifications_only_read_update` bloqueia
  UPDATE de `msg`/`ts_local`/`format_version` (só `read`/`read_at` mudam). Transientes.
  → EN: renderizar no locale do **destinatário** no INSERT (D-I5a). Sem migração de
  tabela; trigger intacto.
- **Auditoria — CONGELADA + IMUTÁVEL por design.** `services/audit_log/record_service.rb:43`
  `I18n.t("audit.#{event}.v#{version}", ...)` sem `locale:` → default pt-BR; grava
  `msg`/`ts_local` em `audit_logs`. Imutabilidade: `REVOKE UPDATE,DELETE FROM
  robotrack_app` + trigger `trg_audit_logs_immutable` (`RAISE EXCEPTION`) + RLS +
  guarda de boot (`immutability_guard.rb`) + snapshot byte-a-byte
  (`spec/fixtures/audit/published_format_strings.yml` + `format_version_guard_spec.rb`);
  `down` é `IrreversibleMigration` com linhas. → EN: congelar no locale do **ator** no
  INSERT; strings `en` como conteúdo das versões; **linhas históricas não são tocadas**
  (D-I5b). **Este é o ponto que torna a alternativa retroativa 🔴 e não-objetivo.**
- **Protocolo — RESOLVIDO NA LEITURA.** `services/reports/commissioning_report_service.rb:60`
  `I18n.t("report.v1.#{key}", **args)` sem `locale:` → default pt-BR; **não** é gravado
  (não há tabela `reports`). Sem assinatura/hash no código — só blocos de assinatura em
  branco e `document_id` de timestamp não-único (`RT-%Y%m%d-%H%M`, tz São Paulo).
  Contrato versionado por processo (PDF assinado em papel). → EN: resolver no locale do
  **leitor** na geração + `en.report.yml`; manter o versionamento; timezone independe
  do idioma (D-I5c). Sem migração.
- **Dado de domínio gravado em pt-BR** (D-I4): enum `task_status`
  (`Pendente|Em Andamento|Concluído|N/A`, migration `...150001_create_tasks.rb`);
  CHECK `robots.application IN (6 literais)` (`robot.rb:12`); 31 tarefas-base/9
  categorias em `task_templates` (`services/task_templates/default_catalog.rb`, grafia
  legada preservada porque a importação casa por `desc`). EN é exibição, nunca rename.

## DECISÕES REGISTRADAS (resumo — detalhe em design.md)

- **D-I1** abordagem própria leve (frontend) + reuso do rails-i18n (backend); sem dep
  pesada (`no-heavy-deps`).
- **D-I5** mensagens congeladas = **congela-para-frente, não reescreve-para-trás**:
  notificação no locale do destinatário, auditoria no locale do ator, relatório no
  locale do leitor; históricos permanecem no idioma de origem.
- **D-I6** persistência: `rt-lang` por dispositivo (base) + `users.locale` na conta
  (durável) — **única migração, 🟡 aditiva reversível por `DROP`**.
- **D-I8** **portão do glossário:** nada de tradução em massa antes da assinatura do
  dono no `GLOSSARIO.md`.

## MAPA DE GRUPOS (ordem + risco de banco)

| Grupo | Conteúdo | Banco |
|---|---|---|
| G0 | planejamento + glossário (este commit) | 🟢 |
| G1 | fundação frontend (store/aplicador, eixo de idioma, parsers dos sweeps, formatação) | 🟢 |
| G2 | seletor (bandeira SVG não-emoji, PortalMenu, 3 superfícies) | 🟢 |
| G3 | extrair inline → `lib/i18n` (ainda pt-BR) | 🟢 |
| G4 | tradução EN frontend + mapa de exibição do dado de domínio | 🟢 **(pós-glossário)** |
| G5 | backend `en.*.yml` + resolução de locale + relatório no locale do leitor | 🟢 **(pós-glossário)** |
| G6 | `users.locale` + congelamento no locale do destinatário/ator | 🟡 **(a única migração)** |

**Não há grupo 🔴.** O caminho 🔴 (re-localização retroativa de auditoria/notificação
via `chave+args` + backfill na tabela imutável) é **não-objetivo explícito** — a
estratégia foi desenhada para não tocar as tabelas congeladas.

## PENDÊNCIAS / HANDOFF

- **Handoff ao dono (bloqueia G1+):** revisar/assinar o `GLOSSARIO.md`, em especial as
  linhas ⚠️ de robótica/comissionamento (avanço, protocolo, status, aplicações,
  categorias e as 31 tarefas-base). As 7 perguntas objetivas estão no fim do glossário.
- Execução dos grupos (G1+) e qualquer teste WSL/E2E ficam para depois da assinatura.
