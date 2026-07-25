import { describe, expect, it } from 'vitest'
import { readFileSync } from 'node:fs'
import { join } from 'node:path'

// impeccable-remediation G1 (§Princípio 1, §DESIGN regra dura) — o gate que trava o
// USO das regras de contraste e alvo de toque nas telas centrais do operador. Os
// TOKENS já são medidos por `contrast.test.ts`; aqui a garantia é que o código USA a
// variante sólida/tinta certa (não a cor crua) e que os controles nº1 do operador
// carregam o piso de toque de luva.
//
// ESCOPO PROPOSITAL: arquivos específicos do G1, não um sweep global. As telas de
// template (Dashboard/Build/Profile/Users/Setup) usam cores cruas e são escopo do
// G5/legado — reprová-las aqui misturaria grupos. Este gate MORDE: reprova a versão
// anterior a G1.

const SRC = join(__dirname, '../src')
const read = (rel: string) => readFileSync(join(SRC, rel), 'utf8')

describe('G1 — alvo de toque do operador de luva', () => {
  it('o slider de progresso carrega a classe de piso de toque', () => {
    expect(read('features/advances/AdvanceControls.tsx')).toMatch(/className="[^"]*\bprogress-slider\b/)
  })

  it('.progress-slider define ≥32px base e ≥40px em ponteiro grosso', () => {
    const css = read('styles/globals.css')
    // bloco base com altura de toque
    expect(css).toMatch(/\.progress-slider\s*\{[^}]*height:\s*32px/)
    // regra de ponteiro grosso (luva/tablet) elevando o alvo para 40px
    expect(css).toMatch(/@media\s*\(pointer:\s*coarse\)\s*\{[\s\S]*\.progress-slider\s*\{[^}]*height:\s*40px/)
  })

  it('o StatusSelect tem piso de toque (40 mobile / 32 desktop) e não depende só de py-0.5', () => {
    const src = read('components/ui/StatusSelect.tsx')
    expect(src).toMatch(/min-h-\[2\.5rem\]/)
    expect(src).toMatch(/sm:min-h-\[2rem\]/)
    // a linha do <select> não usa mais py-0.5 como única altura
    const selectClass = src.match(/className="(label-md[^"]*)"/)?.[1] ?? ''
    expect(selectClass).not.toMatch(/\bpy-0\.5\b/)
  })
})

describe('G1 — contraste por uso do token certo', () => {
  it('Button default/destructive usam a variante SÓLIDA, não bg-primary/bg-destructive', () => {
    const src = read('components/ui/Button.tsx')
    // linha da variante default
    expect(src).toMatch(/default:\s*'bg-accent-solid text-white/)
    expect(src).toMatch(/destructive:\s*'bg-danger-solid text-white/)
    // as cruas some das duas variantes corrigidas
    expect(src).not.toMatch(/default:\s*'bg-primary/)
    expect(src).not.toMatch(/destructive:\s*'bg-destructive/)
  })

  it('AuthPage usa accent-solid nos submits e danger-ink nos erros — nada de bg-primary/text-red-600', () => {
    const src = read('features/auth/AuthPage.tsx')
    expect(src).not.toMatch(/\bbg-primary\b/)
    expect(src).not.toMatch(/\btext-red-600\b/)
    expect(src).toMatch(/\bbg-accent-solid\b/)
    expect(src).toMatch(/\btext-danger-ink\b/)
  })

  it('o badge de não-lidas do sino usa danger-solid + branco (não vermelho-sobre-vermelho)', () => {
    const src = read('features/notifications/NotificationBell.tsx')
    // o bloco do badge (min-w-[1rem] ... rounded-full) usa a sólida + branco
    const badge = src.match(/className="([^"]*min-w-\[1rem\][^"]*)"/)?.[1] ?? ''
    expect(badge).toMatch(/\bbg-danger-solid\b/)
    expect(badge).toMatch(/\btext-white\b/)
    expect(badge).not.toMatch(/\bbg-danger\b(?!-solid)/)
    expect(badge).not.toMatch(/\btext-danger-ink\b/)
  })

  it('o IconButton foca com ring-ring (AA), não ring-accent', () => {
    const src = read('components/ui/IconButton.tsx')
    expect(src).toMatch(/focus-visible:ring-ring/)
    expect(src).not.toMatch(/focus-visible:ring-accent/)
  })
})
