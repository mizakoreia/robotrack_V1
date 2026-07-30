> **Legenda de risco de banco:** 🟢 sem migração · 🟡 migração aditiva reversível por
> `DROP` · 🔴 migração com reversão **NÃO-trivial**.
>
> **PORTÃO:** nenhuma tradução em massa (G3/G4/dado de domínio) começa antes de o dono
> **assinar o `GLOSSARIO.md`**. G0 é só planejamento.

## 0. Planejamento (G0) 🟢

- [x] 0.1 Auditar o estado real de i18n (frontend: `lib/i18n` + inline + sweeps;
  backend: rails-i18n, `en` ausente, mensagens congeladas de notificação/auditoria/
  relatório) e reconciliar design × realidade em `EXECUCAO.md`.
- [x] 0.2 Harvest de domínio e materialização do `GLOSSARIO.md` (domínio + 6 aplicações
  + 9 categorias + 31 tarefas-base), com as linhas duvidosas marcadas ⚠️ para o dono.
- [x] 0.3 Materializar a change (proposal/design/specs/tasks/EXECUCAO) e validar
  `--strict` verde antes de qualquer código.
- [x] 0.4 **Handoff ao dono:** revisar e confirmar o `GLOSSARIO.md`. **APROVADO** —
  7 decisões fechadas (ver topo do `GLOSSARIO.md`); execução liberada.

## 1. Fundação de i18n no frontend (G1) 🟢 — FECHADO

- [x] 1.1 `useLanguageStore` (`store/languageStore.ts`, Zustand + `persist` →
  `localStorage['rt-lang']` via `zustandStorage`, default `pt-BR`) + `useLanguage()`
  (`hooks/useLanguage.ts`) e `LanguageProvider` (`components/LanguageProvider.tsx`,
  remount por `key={lang}`) que aplicam `document.documentElement.lang`. Espelho do
  `themeStore`/`useTheme`/`ThemeProvider`. (Prova: `languageAxis.test.ts` — `localeTag`
  acompanha o idioma; store default pt-BR.)
- [x] 1.2 Eixo de idioma nos 11 módulos `lib/i18n` via `defineText(ptBR, en)`
  (`lib/i18n/defineText.ts` + `lang.ts`): Proxy que resolve a chave no idioma corrente
  (string, função, plural, sub-objeto aninhado) mantendo o MESMO nome de export (os ~29
  consumidores não mudaram). pt-BR canônico no módulo; en em `<x>.en.ts` (tradução do
  glossário JÁ aplicada — cobre G4.1). (Prova: `languageAxis.test.ts` 7/7 — troca
  pt-BR⇄en em string/função/plural/aninhado/gênero + enumeração preservada.)
- [x] 1.3 Parser da **regra G** do `convention-sweep.test.ts` atualizado (exclui
  `.en.ts`); os demais sweeps (`invitations`/`feedback`.i18n, `progress-label`,
  `report/literalSweep`) passam sem mudança de parser porque o default pt-BR + a
  enumeração do Proxy preservam a forma que eles leem. (Prova: sweeps 28/28.)
- [x] 1.4 Parametrizados por locale os 3 pontos de EXIBIÇÃO (`report/format.ts`,
  `feedback/FeedbackInbox.tsx`, `robot-tasks/HistoryModal.tsx`) via `localeTag()`. Os 2
  semânticos (`AssignmentModal` `toLocaleLowerCase` de dedup; `CatalogPanel`
  `localeCompare` de dado pt-BR) ficam FIXOS de propósito; `kpi/PerformanceIndicators`
  é legado de template (fora do app). (Prova: `languageAxis.test.ts` cobre `localeTag`.)
- [x] 1.5 Verificação do grupo: sweeps 28/28; suíte completa **640/640** (o único
  timeout, `offline/queue.test.ts`, passa isolado em 5,7s — contenção de CPU sob a
  suíte, sem relação com i18n); `tsc --noEmit` limpo.

## 2. Seletor de idioma (G2 — impeccable) 🟢 — FECHADO

- [x] 2.1 `components/icons/Flag.tsx` — bandeiras **BR/GB em SVG** com fills próprios
  (`aria-hidden`), exceção documentada ao sprite monocromático. (Prova: `no-emoji.test.ts`
  passa — inclusive pegou e removeu um emoji citado por engano num comentário.)
- [x] 2.2 `components/LanguageSelect.tsx` — **controle** (não badge): variante `menu`
  (`PortalMenu` com dois alvos explícitos Português/English, gatilho com bandeira +
  código, `aria-label` "Idioma / Language", ≥40px) e `segmented` (dois botões
  `aria-pressed`, como o tema). Bandeira `aria-hidden`; nome acessível = idioma.
  (Prova: `components/__tests__/LanguageSelect.test.tsx` 4/4 — nome acessível, alvo
  `min-h-[40px]`, dois `menuitem`, troca no store, `aria-pressed`.)
- [x] 2.3 Colocado nas 3 superfícies: menu da conta (`AppShell`, rodapé da sidebar),
  painel `AppearancePanel` (segmented, junto do tema) e `AuthPage` (pré-login, canto
  superior). (Prova: regra G do `convention-sweep` verde — sem colisão de nome.)
- [x] 2.4 Verificação do grupo: `no-emoji` + `convention-sweep` + `LanguageSelect` +
  i18n sweeps 31/31; suíte completa 650/651 (só o flake de CPU do offline/queue); tsc
  limpo. Prova visual real virá no deploy do Render (build da `main`).

## 3. Extração dos literais inline → `lib/i18n` (G3) 🟢 — FECHADO

Feito **com o EN já traduzido** (glossário confirmado) — o eixo `defineText` recebe
pt-BR + en de uma vez, então G3 já entrega os dois idiomas nas superfícies migradas.

- [x] 3.1 Chrome do `AppShell` → `lib/i18n/shell.ts` (nav/menu da conta/topbar/gaveta;
  `nav.ts` ganhou `key` e o rótulo é resolvido no render por `shellText.nav[key]`).
  `AuthPage` → `lib/i18n/auth.ts` (login/cadastro/validações/erros 401/409/422). (Prova:
  regra G verde — "Convidar pessoa" resolve ao mesmo valor pt-BR da allowlist; AppShell
  13/13; auth 25/25.)
- [x] 3.2 `AjudaPage` (476 linhas) → `lib/i18n/ajuda.ts` (modelo rico: seções/TOC da
  MESMA lista de dados, âncoras `#id` preservadas). Telas Visão Geral/Projeto/Célula/
  Robô-Tarefas/`StorageWarning`/gráficos → `lib/i18n/pages.ts`. (Prova: 82 testes de
  páginas/componentes verdes; AjudaPage 4/4.)
- [x] 3.3 Verificação do grupo: `no-emoji` + `convention-sweep` + `progress-label` +
  `report/literalSweep` + provas i18n **39/39**; suíte completa **654/655** (só o flake
  de CPU do offline/queue); `tsc` limpo. Dado de domínio (status/aplicações/tarefas-base)
  **não** foi tocado — fica para o mapa de exibição do G4.

## 4. Tradução EN — frontend (G4) 🟢 — FECHADO

- [x] 4.1 EN de todos os módulos `lib/i18n` preenchido com o glossário confirmado —
  **feito junto de G1/G2/G3** (o eixo `defineText` recebe pt-BR + en de uma vez, então
  cada módulo já nasceu bilíngue). Paridade de chaves garantida pelo tipo
  (`<x>En: <XText>`). (Prova: `languageAxis.test.ts` 7/7.)
- [x] 4.2 `lib/i18n/dataLabels.ts` — mapa de exibição EN para os VALORES de dado
  (4 status, 6 aplicações, 9 categorias, 31 tarefas-base) chaveado pelo valor pt-BR do
  banco (grafia legada preservada nas chaves). Aplicado nos render sites: `StatusCell`
  (badge + opções render-time, `value` continua pt-BR), `MyTasksPage`, `CellPage`,
  `RobotTaskTablePage` (aplicação/categoria/desc), `CatalogPanel` (categoria/desc/
  filtros de aplicação), `AcoesCell`, `BatchRobotWizard`. (Prova: `dataLabels.test.ts`
  4/4 — em pt-BR devolve o valor; em en traduz o RÓTULO; valor custom cai no fallback;
  `Concluído`→`Done`, `Solda Ponto`→`Spot Welding`, `E. Trajetórias`→`E. Trajectories`.)
- [x] 4.3 Verificação do grupo: `dataLabels` + telas de dado (robot-tasks/settings/
  pages) **129/129**; suíte completa **654/655** (só o flake de CPU do offline/queue);
  `tsc` limpo. O relatório (dado no documento) fica para o G5, que resolve o locale do
  leitor no servidor. Prova visual real no deploy do Render.

## 5. Backend en.*.yml + resolução de locale (G5) 🟢 — FECHADO

- [x] 5.1 Criados os 10 `config/locales/en.*.yml` espelhando os `pt-BR.*.yml` (incl.
  `report.v1.*`, `notifications.v1.*`, `audit.*.v1`), com paridade de chaves e de
  interpolação (`%{...}`/`%%`) verificada. Glossário: report `Concluído`→**Completed**,
  título→"COMMISSIONING PROTOCOL", `raw_count`→"Task completion", papéis Owner/Can edit/
  Can view. (Prova: boot em test carrega `:en`; renderização en confirmada.)
- [x] 5.2 `app/middleware/locale_middleware.rb` — resolve o locale por requisição
  (`X-Locale` do seletor → `Accept-Language` → default pt-BR) e embrulha em
  `I18n.with_locale` (restaura ao sair). Registrado em `config/application.rb`; fallback
  `en → pt-BR`. Frontend: `lib/api/client.ts` envia `X-Locale` = `rt-lang` em toda
  requisição. (Prova: `spec/middleware/locale_middleware_spec.rb` 6/6 — prioridade,
  fallback, não-vazamento entre requisições.)
- [x] 5.3 `CommissioningReportService#t` (já usava `I18n.t` sem locale) passa a resolver
  `report.v1.*` no locale da requisição; `document_id`/timezone independem do idioma.
  (Prova: `commissioning_report_spec` — `X-Locale: en` → título "COMMISSIONING PROTOCOL"
  e distribuição "Completed/Pending"; sem header → pt-BR, não regride.)
- [x] 5.4 Verificação do grupo: middleware + report **17/17**; specs sensíveis a i18n
  (audit/format-guard, notificações, erros, autorização) **130/130** (2 pending
  pré-existentes de superuser). pt-BR.*.yml intactos; nenhuma versão `vN` sobrescrita.

## 6. Preferência na conta + congelamento server-side (G6) 🟡 — MIGRAÇÃO (a única)

- [ ] 6.0 **Backup/rollback:** a migração é aditiva e reverte por `DROP COLUMN`;
  registrar o `down` explícito antes de aplicar (tarefa destrutiva exige rollback
  imediatamente antes — aqui o `down` é o próprio rollback).
- [ ] 6.1 Migração aditiva `users.locale text NOT NULL DEFAULT 'pt-BR'` +
  `CHECK locale IN ('pt-BR','en')`. Regenerar `structure.sql`. (Prova: `INSERT` com
  `locale='es'` falha no CHECK; default preserva usuários existentes em pt-BR.)
- [ ] 6.2 `PATCH /users/me` que altera **só o próprio** locale (política, não UI); o
  cliente sincroniza `rt-lang` ↔ conta no login/troca. (Prova de negação: não há rota
  que altere locale de outra pessoa.)
- [ ] 6.3 `MessageBuilder`/`CreateService` congelam a `msg` no locale do **destinatário**
  (deixa de fixar `LOCALE=:'pt-BR'`); `RecordService` congela no locale do **ator**.
  Trigger de notificações e imutabilidade de auditoria **intactos**. (Prova: dois
  destinatários em idiomas diferentes → duas msg congeladas; UPDATE de `audit_logs.msg`
  ainda levanta exceção.)
- [ ] 6.4 Verificação do grupo: specs de notificação (idioma por destinatário) e
  auditoria (idioma por ator, imutabilidade preservada) verdes.

## 7. Documentação (parte de cada push, não posterior)

- [ ] 7.1 Ao fechar cada grupo, atualizar `CONTINUIDADE.md` (estado/tip) e, se mudar
  procedimento/seletor de teste, `VALIDACAO_WSL.md`; registrar decisões no
  `EXECUCAO.md`. Ao remover/renomear controle, procurar o rótulo nos `.md`.
