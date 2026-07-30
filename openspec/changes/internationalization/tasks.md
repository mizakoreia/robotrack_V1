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
- [ ] 0.4 **Handoff ao dono:** revisar e confirmar o `GLOSSARIO.md` (especialmente
  robótica/comissionamento). *Bloqueia G1+.*

## 1. Fundação de i18n no frontend (G1) 🟢

- [ ] 1.1 `useLanguageStore` (Zustand + `persist` → `localStorage['rt-lang']` via
  `zustandStorage`, default `pt-BR`) e `useLanguage()` que aplica
  `document.documentElement.lang`. Espelho exato do `themeStore`/`useTheme`.
  (Prova: recarregar com `rt-lang='en'` abre em en; storage bloqueado mantém en só na
  sessão.)
- [ ] 1.2 Introduzir o eixo de idioma nos 11 módulos `lib/i18n` mantendo **literais
  planos de uma linha** por chave, com resolvedor `L(...)`; ramo por idioma nas 41
  funções de plural/interpolação (via `Intl.PluralRules`). *pt-BR e en convivem; en
  ainda placeholder até o glossário.* (Prova: `metricLabel` e um plural retornam a
  string do idioma corrente nos dois idiomas.)
- [ ] 1.3 **Atualizar os parsers dos sweeps** para a nova forma: regra G do
  `convention-sweep.test.ts` e `invitations.i18n.test.ts`/`feedback.i18n.test.ts`/
  `progress-label.test.tsx`/`report/literalSweep.test.ts`. (Prova: os cinco sweeps
  passam com a forma nova; a falha proposital de um literal inline ainda é pega.)
- [ ] 1.4 Parametrizar por locale os 6 pontos de formatação (`report/format.ts`,
  `feedback/FeedbackInbox.tsx`, `robot-tasks/HistoryModal.tsx`,
  `robot-tasks/AssignmentModal.tsx`, `settings/CatalogPanel.tsx`,
  `kpi/PerformanceIndicators.tsx`). (Prova: uma data e um número formatam conforme o
  locale corrente.)
- [ ] 1.5 Verificação do grupo: `npm test` dos sweeps + os testes de store/aplicador
  verdes.

## 2. Seletor de idioma (G2 — impeccable) 🟢

- [ ] 2.1 Asset/sprite de bandeira **BR/GB em SVG (não emoji)**, com fills próprios,
  documentado como exceção ao sprite monocromático. (Prova: `no-emoji.test.ts` passa;
  contraste/visibilidade AA nos dois temas.)
- [ ] 2.2 Primitivo do seletor: `PortalMenu` com dois alvos explícitos (Português/
  English), ≥40px, `aria-label` "Idioma / Language", bandeira `aria-hidden`, texto
  visível. **Controle, não badge.** (Prova: leitor de tela anuncia o idioma, não a
  bandeira; alvo ≥40px medido.)
- [ ] 2.3 Colocar o seletor no menu da conta (`AppShell`, ao lado de "Alternar tema"),
  no `AppearancePanel` e na `AuthPage`. (Prova: regra G não acusa colisão de nome; o
  seletor troca a UI e o `lang` nas três superfícies.)
- [ ] 2.4 Verificação do grupo: testes de a11y/contraste + `no-emoji` verdes.

## 3. Extração dos literais inline → `lib/i18n` (G3) 🟢

- [ ] 3.1 Extrair o chrome do `AppShell` (itens de menu, aria-labels do topbar/nav) e
  a `AuthPage` (login/cadastro/validações) para módulos `lib/i18n`, **ainda em pt-BR**.
- [ ] 3.2 Extrair `AjudaPage` (476 linhas de prosa) e as telas Visão Geral/hierarquia/
  gráficos/`StorageWarning` para `lib/i18n`, **ainda em pt-BR**.
- [ ] 3.3 Verificação do grupo: um sweep novo confirma que as superfícies migradas não
  têm mais literal pt-BR de UI inline (na fronteira coberta).

## 4. Tradução EN — frontend (G4) 🟢 — **depende do glossário assinado**

- [ ] 4.1 Preencher o `en` de todos os módulos `lib/i18n` conforme o `GLOSSARIO.md`
  aprovado. (Prova: paridade de chaves pt-BR/en; nenhuma chave sem en.)
- [ ] 4.2 Mapa de exibição EN para dado de domínio (status/aplicações/categorias/
  tarefas-base) chaveado pelo valor pt-BR do banco — **exibição, sem tocar o dado**.
  (Prova: status `Concluído` mostra o rótulo EN e a coluna continua `Concluído`.)
- [ ] 4.3 Verificação do grupo: um passe visual PT⇄EN nas telas-chave (Visão Geral,
  Robô/Tarefas, Relatório, Configurações, entrada) + sweeps verdes.

## 5. Backend en.*.yml + resolução de locale (G5) 🟢 — **depende do glossário**

- [ ] 5.1 Criar `config/locales/en.*.yml` espelhando os 10 `pt-BR.*.yml` (incl.
  `report.v1.*`, `notifications.v1.*`, `audit.*.vN`). (Prova: um sweep de paridade de
  chaves pt-BR↔en verde; nenhum `missing_translation` sob `:en`.)
- [ ] 5.2 Resolução de locale por requisição (`around_action`/middleware +
  `I18n.with_locale`) a partir da conta e, subsidiariamente, `Accept-Language`.
  (Prova: requisição de conta en renderiza texto server-side em en.)
- [ ] 5.3 `CommissioningReportService#t` resolve `report.v1.*` no locale do leitor na
  geração (timezone permanece independente do idioma). (Prova: Protocolo emitido por
  leitor en sai com rótulos em en; `document_id`/horário inalterados.)
- [ ] 5.4 Verificação do grupo: specs de request cobrindo pt-BR e en; sweep de literal
  do relatório estendido a en.

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
