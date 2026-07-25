# Product

## Register

product

## Users

Dois papéis, um chão de fábrica:

- **Operador de comissionamento** — registra o avanço das tarefas de cada robô no
  galpão. Contexto físico que MANDA no design: **luva** (alvos de toque grandes),
  **luz de galpão** (contraste alto, legível de longe), celular/tablet na mão, às
  vezes **sem rede** (offline acontece). O trabalho é repetitivo e diário: abrir o
  robô, arrastar o progresso, registrar a observação.
- **Dono / gestor do workspace** — monta a hierarquia (projeto → célula → robô →
  tarefa), convida gente para colaborar (papel `edit`/`view`), acompanha o
  progresso agregado e gera o **Protocolo de Comissionamento** (o artefato formal
  que se assina). Trabalha mais no desktop.

Cada usuário é dono do próprio workspace e pode ser convidado a colaborar no de
outros.

## Product Purpose

RoboTrack acompanha o **comissionamento de robôs industriais** ao longo de uma
hierarquia (projeto → célula → robô → tarefa), do primeiro parafuso ao protocolo
assinado. Substitui um sistema legado (PWA + Firestore) por Rails 8 API-only +
React 18/TS, com isolamento por workspace forçado no banco (RLS), tempo real
(ActionCable), fila offline (PWA) e uma trilha de auditoria imutável.

Sucesso = o operário registra o avanço em segundos sem errar, o gestor enxerga o
progresso real (duas métricas nomeadas, nunca "progresso" solto), e o Protocolo de
Comissionamento sai íntegro e conferível. A ferramenta serve ao trabalho; ela não
compete pela atenção.

## Brand Personality

**Funcional e direto.** Três palavras: *claro, confiável, sem enfeite*. A confiança
vem da CLAREZA (contraste, hierarquia, estado honesto), não da decoração. Voz em
pt-BR, direta, sem jargão de marketing — a mesma frase que o operário lê num momento
de decisão. Uma ferramenta de trabalho de gente que usa luva, não um produto para
impressionar numa demo.

## Anti-references

- **SaaS genérico.** Grades de cards idênticos, hero com número gigante + rótulo
  pequeno, gradientes decorativos, "eyebrow" em maiúsculas sobre cada seção. O
  visual template que grita IA. Já há bans no design-system (texto em gradiente,
  borda-faixa lateral, glassmorphism decorativo) — mantê-los.
- **Dashboard corporativo pesado** (cinza sobre cinza, tudo com borda e sombra, sem
  hierarquia) — o oposto do "legível de longe".

## Design Principles

1. **Legível sob luz de galpão.** Contraste e tamanho servem o AMBIENTE, não a
   estética. Corpo ≥ 4.5:1, não-texto ≥ 3:1, alvo de toque ≥ 32px (excede os 24px de
   WCAG 2.5.8 — é requisito de luva). Cinza-claro "por elegância" é proibido.
2. **Estado honesto.** O operário NUNCA acha que salvou quando não salvou. Offline,
   pendente e bloqueado são explícitos; "salvo" só quando salvou de verdade.
3. **A invariante mora no banco; a UI não mente sobre ela.** Papel e autoridade vêm
   do servidor (RLS/owner_user_id), nunca do cliente. A UI desabilita o que seria
   negado, mas não é ela que autoriza.
4. **Duas métricas nomeadas, nunca "progresso" solto (D15).** Ponderado ≠ contagem
   crua; o número que a pessoa assina é inequívoco, com o nome ao lado.
5. **Cada pixel serve a uma tarefa.** Sem enfeite. Se um elemento não ajuda o
   operário a registrar ou o gestor a decidir, ele não entra.

## Accessibility & Inclusion

WCAG **AA**, medido no CI (não aspiracional): `tests/contrast.test.ts` reprova
contraste < 4.5:1 (corpo) / 3:1 (não-texto), composição alfa das camadas incluída.
Alvos de toque ≥ 32px (luva). `prefers-reduced-motion` zera animações. Live regions
no shell (`#rt-status` polite, `#rt-alerts`
assertive). Foco visível AA (ring ≥ 3:1). Tema NÃO segue o SO (escuro é o primário;
guarda de CI). Rótulos de métrica sempre nomeados para leitor de tela (`role=img` no
anel, `role=progressbar` nas barras). A wave `quality-and-accessibility` é o gate que
trava tudo isso.
