import { describe, expect, it } from 'vitest'
import { readFileSync } from 'node:fs'
import { join } from 'node:path'

// design-system 7.4 (D-DS-6) — os keyframes de motion na config e a garantia de
// que nenhuma curva de saída tem bounce. (A luz ambiente que seguia o mouse — as
// três camadas `.ambient`/`.glass-sheen`/`.glass` — foi REMOVIDA; ver EXECUCAO.md
// da change design-system, decisão de remoção.)
const TW = readFileSync(join(__dirname, '../tailwind.config.js'), 'utf8')

describe('keyframes de motion (7.4)', () => {
  it('declara viewEnter/menuIn/modalPop/successPulse e as animações', () => {
    ;['viewEnter', 'menuIn', 'modalPop', 'successPulse'].forEach((k) => expect(TW).toMatch(new RegExp(`${k}:`)))
    ;['view-enter', 'menu-in', 'modal-pop', 'success-pulse'].forEach((a) => expect(TW).toContain(`'${a}':`))
  })

  it('nenhuma cubic-bezier tem componente y fora de [0,1] (sem bounce)', () => {
    const beziers = [...TW.matchAll(/cubic-bezier\(([^)]+)\)/g)].map((m) => m[1].split(',').map(Number))
    expect(beziers.length).toBeGreaterThan(0)
    beziers.forEach(([, y1, , y2]) => {
      expect(y1).toBeGreaterThanOrEqual(0)
      expect(y1).toBeLessThanOrEqual(1)
      expect(y2).toBeGreaterThanOrEqual(0)
      expect(y2).toBeLessThanOrEqual(1)
    })
  })
})
