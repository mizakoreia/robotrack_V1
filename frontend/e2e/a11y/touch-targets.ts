import type { Page } from '@playwright/test'

// quality-and-accessibility 5.5 (`PRODUCT.md §Users`) — o auditor de alvo de
// TOQUE. 32px é requisito de AMBIENTE (dedo de luva, escuro do galpão) e excede os
// 24px de WCAG 2.5.8. Mede o retângulo EFETIVO de cada controle tocável em 375×812:
//   - aceita área ESTENDIDA por pseudo-elemento (`::before`/`::after` absoluto com
//     inset — o padrão de "aumentar o toque sem inchar o layout");
//   - REPROVA sobreposição entre duas áreas estendidas ADJACENTES (o dedo de luva
//     aciona o botão errado — pior que o alvo pequeno);
//   - ISENTA link de texto em FLUXO (WCAG 2.5.8 isenta o link inline em parágrafo).
//
// Roda inteiro no contexto da página (uma passagem de layout), devolve os achados.

export const MIN_TOUCH_PX = 32

export interface TouchViolation {
  reason: 'pequeno' | 'sobreposicao'
  label: string
  detail: string
}

export async function auditTouchTargets(page: Page): Promise<TouchViolation[]> {
  return page.evaluate((min) => {
    interface Rect {
      top: number
      left: number
      right: number
      bottom: number
    }
    const violations: { reason: 'pequeno' | 'sobreposicao'; label: string; detail: string }[] = []

    const nome = (el: Element): string => {
      const aria = el.getAttribute('aria-label')
      const txt = (el.textContent || '').trim().replace(/\s+/g, ' ').slice(0, 40)
      return aria || txt || el.getAttribute('title') || el.tagName.toLowerCase()
    }

    // Extensão por pseudo-elemento absoluto com inset (o padrão de área de toque
    // ampliada). Devolve o retângulo efetivo e se de fato ESTENDEU a base.
    const pseudoInset = (el: Element, base: Rect): { rect: Rect; extended: boolean } => {
      let rect = { ...base }
      let extended = false
      for (const sel of ['::before', '::after']) {
        const cs = getComputedStyle(el, sel)
        if (cs.content === 'none' || cs.position !== 'absolute') continue
        const px = (v: string) => (v.endsWith('px') ? parseFloat(v) : NaN)
        const tp = px(cs.top)
        const lf = px(cs.left)
        const rt = px(cs.right)
        const bt = px(cs.bottom)
        const cand: Rect = {
          top: Number.isNaN(tp) ? rect.top : base.top + tp,
          left: Number.isNaN(lf) ? rect.left : base.left + lf,
          right: Number.isNaN(rt) ? rect.right : base.right - rt,
          bottom: Number.isNaN(bt) ? rect.bottom : base.bottom - bt,
        }
        // Só conta como extensão se AUMENTA a área (inset negativo).
        if (cand.right - cand.left > rect.right - rect.left || cand.bottom - cand.top > rect.bottom - rect.top) {
          rect = {
            top: Math.min(rect.top, cand.top),
            left: Math.min(rect.left, cand.left),
            right: Math.max(rect.right, cand.right),
            bottom: Math.max(rect.bottom, cand.bottom),
          }
          extended = true
        }
      }
      return { rect, extended }
    }

    // Link de texto em fluxo: <a> com display inline DENTRO de texto corrido (o pai
    // tem texto além do próprio link). Isento (WCAG 2.5.8).
    const isInlineTextLink = (el: Element): boolean => {
      if (el.tagName !== 'A' || el.getAttribute('role') === 'button') return false
      const disp = getComputedStyle(el).display
      if (!disp.startsWith('inline')) return false
      const parentText = (el.parentElement?.textContent || '').trim()
      const ownText = (el.textContent || '').trim()
      return parentText.length > ownText.length // há texto em volta → é link em fluxo
    }

    const sel =
      'button, a[href], input:not([type=hidden]), select, textarea, ' +
      '[role=button], [role=link], [role=switch], [role=checkbox], [role=tab], [tabindex]:not([tabindex="-1"])'
    const candidatos = Array.from(document.querySelectorAll(sel))
    const estendidos: { label: string; rect: Rect }[] = []

    for (const el of candidatos) {
      if (el.getAttribute('aria-hidden') === 'true') continue
      if ((el as HTMLButtonElement).disabled) continue
      const base = el.getBoundingClientRect()
      if (base.width === 0 || base.height === 0) continue // fora do DOM/oculto
      if (getComputedStyle(el).visibility === 'hidden') continue
      if (isInlineTextLink(el)) continue

      const { rect, extended } = pseudoInset(el, base)
      const w = rect.right - rect.left
      const h = rect.bottom - rect.top
      if (w < min || h < min) {
        violations.push({
          reason: 'pequeno',
          label: nome(el),
          detail: `${Math.round(w)}×${Math.round(h)}px < ${min}px (efetivo${extended ? ', já com pseudo' : ''})`,
        })
      }
      if (extended) estendidos.push({ label: nome(el), rect })
    }

    // Sobreposição entre áreas ESTENDIDAS adjacentes.
    const intersecta = (a: Rect, b: Rect) =>
      a.left < b.right && b.left < a.right && a.top < b.bottom && b.top < a.bottom
    for (let i = 0; i < estendidos.length; i++) {
      for (let j = i + 1; j < estendidos.length; j++) {
        if (intersecta(estendidos[i].rect, estendidos[j].rect)) {
          violations.push({
            reason: 'sobreposicao',
            label: `${estendidos[i].label} × ${estendidos[j].label}`,
            detail: 'duas áreas de toque estendidas se interceptam',
          })
        }
      }
    }
    return violations
  }, MIN_TOUCH_PX)
}

export function describeTouch(v: TouchViolation[]): string {
  return v.map((x) => `  [${x.reason}] ${x.label} — ${x.detail}`).join('\n')
}
