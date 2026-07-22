import { describe, expect, it } from 'vitest'
import { render } from '@testing-library/react'
import { Icon } from '../Icon'
import { IconSprite, ICON_NAMES } from '../sprite'

// design-system 3.2 (D-DS-8) — o Icon herda a cor por currentColor e é
// decorativo por padrão. Nenhum `<symbol>` fixa stroke/fill literal (senão o
// chevron do StatusSelect para de herdar a tinta do status).

describe('Icon (D-DS-8)', () => {
  it('é aria-hidden por padrão e vira role=img com title', () => {
    const { container, rerender } = render(<Icon name="check" />)
    expect(container.querySelector('svg')).toHaveAttribute('aria-hidden', 'true')
    rerender(<Icon name="check" title="pronto" />)
    const svg = container.querySelector('svg')!
    expect(svg).not.toHaveAttribute('aria-hidden')
    expect(svg).toHaveAttribute('aria-label', 'pronto')
  })

  it('aponta para o símbolo do sprite por <use href="#i-...">', () => {
    const { container } = render(<Icon name="chevron-down" />)
    expect(container.querySelector('use')).toHaveAttribute('href', '#i-chevron-down')
  })

  it('nenhum <symbol> do sprite fixa stroke/fill literal (herda currentColor)', () => {
    const { container } = render(<IconSprite />)
    container.querySelectorAll('symbol').forEach((sym) => {
      // stroke declarado é currentColor; nunca uma cor literal (#, rgb, hsl…)
      const stroke = sym.getAttribute('stroke')
      expect(stroke === null || stroke === 'currentColor', `${sym.id} stroke=${stroke}`).toBe(true)
      expect(sym.getAttribute('fill') ?? 'none').toMatch(/^(none|currentColor)$/)
    })
  })

  it('cada nome exportado tem um símbolo correspondente', () => {
    const { container } = render(<IconSprite />)
    ICON_NAMES.forEach((n) => {
      expect(container.querySelector(`#i-${n}`), `símbolo i-${n} ausente`).toBeTruthy()
    })
  })
})
