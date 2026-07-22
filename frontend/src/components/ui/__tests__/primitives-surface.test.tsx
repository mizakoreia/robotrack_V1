import { describe, expect, it } from 'vitest'
import { render, screen } from '@testing-library/react'
import { EntityCard } from '../EntityCard'
import { ProgressRing } from '../ProgressRing'
import { Hub } from '../Hub'

// design-system 5.4 (§5.2) — cada teste REPROVA a implementação ingênua
// correspondente (badge dentro do título; ponto no anel a 0%; barra animando
// width). jsdom não faz layout (offsetTop = 0), então a proteção é ESTRUTURAL.

describe('EntityCard — badge é irmão do título (5.1)', () => {
  it('o badge NÃO é descendente do título; footer é mt-auto; card é h-full', () => {
    const { container } = render(
      <EntityCard
        title="Robô de solda ponto lateral direito — estação 07"
        icon="check"
        badge={<span>Concluído</span>}
        footer={<span>rodapé</span>}
      />,
    )
    const heading = screen.getByRole('heading', { level: 3 })
    const badge = screen.getByText('Concluído')
    // o modo de falha: badge dentro do <h3> empurra a linha e desalinha os anéis
    expect(heading.contains(badge)).toBe(false)

    const card = container.firstElementChild as HTMLElement
    expect(card.className).toContain('h-full')
    expect(container.querySelector('.mt-auto')).toBeTruthy()
  })
})

describe('ProgressRing — omite o path a 0% (5.2)', () => {
  it('a 0% o DOM tem só o trilho (nenhum path/círculo de progresso)', () => {
    const { container } = render(<ProgressRing value={0} />)
    const circles = container.querySelectorAll('circle')
    expect(circles).toHaveLength(1) // só o trilho
    // nenhum círculo com stroke-dasharray começando em 0 (o ponto arredondado)
    container.querySelectorAll('circle[stroke-dasharray]').forEach((c) => {
      expect(c.getAttribute('stroke-dasharray')).not.toMatch(/^0[,\s]/)
    })
  })

  it('a 45% há o trilho + o path de progresso com dasharray "45, 100"', () => {
    const { container } = render(<ProgressRing value={45} />)
    expect(container.querySelectorAll('circle')).toHaveLength(2)
    expect(container.querySelector('circle[stroke-dasharray]')?.getAttribute('stroke-dasharray')).toBe('45, 100')
    expect(screen.getByRole('img')).toHaveAttribute('aria-label', '45%')
  })
})

describe('Hub — barra anima por transform, não width (5.3)', () => {
  it('a 45% o transform é scaleX(0.45), a width é constante e a transição é de transform', () => {
    const { container } = render(<Hub label="Progresso físico" value={45} valueText="12/40" />)
    const bar = container.querySelector('[role="progressbar"]')!
    expect(bar).toHaveAttribute('aria-valuenow', '45')

    const fill = bar.firstElementChild as HTMLElement
    expect(fill.style.transform).toBe('scaleX(0.45)')
    expect(fill.className).toContain('w-full') // width constante 100%
    expect(fill.className).toContain('transition-transform') // não transition-all/width
    expect(fill.className).not.toMatch(/transition-\[?width/)
  })
})
