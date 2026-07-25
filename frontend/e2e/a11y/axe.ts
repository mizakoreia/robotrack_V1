import type { Page } from '@playwright/test'
import AxeBuilder from '@axe-core/playwright'

// quality-and-accessibility 5.6 (D-QA-3) — o gate `@axe-core/playwright`. O tema
// CLARO é o menos usado e é onde a regressão mora (a tinta de `N/A` a 2.25:1
// passou despercebida no claro), então o gate roda nos DOIS temas.

export type Theme = 'dark' | 'light'

// Força o tema aplicando `.light` + `data-theme` no root — o MESMO efeito que o
// script anti-FOUC do `index.html` produz a partir de `localStorage['rt-theme']`.
// Via `evaluate` (não `reload`) para não perder o estado da tela (ex.: um modal
// aberto na variante 5.6 que audita o modal de avanço).
export async function setTheme(page: Page, theme: Theme): Promise<void> {
  await page.evaluate((t) => {
    document.documentElement.classList.toggle('light', t === 'light')
    document.documentElement.setAttribute('data-theme', t)
  }, theme)
}

export interface AxeFinding {
  id: string
  impact: string | null | undefined
  nodes: number
  help: string
  target: string
}

// Roda o axe e devolve as NÃO-APROVAÇÕES: as `violations` MAIS os `incomplete` de
// CONTRASTE. `incomplete` de contraste = o axe não conseguiu decidir sozinho —
// tipicamente texto sobre superfície de VIDRO/gradiente, que é exatamente onde a
// regressão de contraste do RoboTrack mora (todas as telas são de vidro). Contar
// `incomplete` como aprovação esvaziaria o gate justamente ali (D-QA-3). Os demais
// `incomplete` (que pedem julgamento humano fora de contraste) NÃO entram — senão
// o gate vira ruído e é desligado.
export async function axeFindings(page: Page): Promise<AxeFinding[]> {
  const results = await new AxeBuilder({ page })
    .withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa'])
    .analyze()

  const toFinding = (r: {
    id: string
    impact?: string | null
    help: string
    nodes: { target: unknown[] }[]
  }): AxeFinding => ({
    id: r.id,
    impact: r.impact,
    nodes: r.nodes.length,
    help: r.help,
    target: r.nodes.map((n) => String(n.target[0] ?? '')).join(', '),
  })

  const contrastIncomplete = results.incomplete.filter((r) => r.id === 'color-contrast')
  return [...results.violations.map(toFinding), ...contrastIncomplete.map(toFinding)]
}

// Mensagem legível quando o gate reprova — nomeia regra + alvo, para o conserto
// não virar caça ao tesouro no relatório do CI.
export function describeFindings(findings: AxeFinding[]): string {
  return findings.map((f) => `  [${f.impact ?? 'contraste'}] ${f.id} (${f.nodes}×): ${f.help} — ${f.target}`).join('\n')
}
