import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { render, screen, fireEvent, cleanup } from '@testing-library/react'

// owner-only-card-delete — o gesto de swipe-to-reveal do EntityCard (mobile).
// matchMedia é mockado por query: ponteiro grosso (toque) LIGA o gesto; movimento
// reduzido controla a animação. Sem esse mock o jsdom devolveria o fallback.
let coarse = true
let reducedMotion = false
vi.mock('@/lib/useMediaQuery', () => ({
  useMediaQuery: (query: string, fallback = true) => {
    if (query.includes('pointer: coarse')) return coarse
    if (query.includes('prefers-reduced-motion')) return reducedMotion
    return fallback
  },
}))

import { EntityCard } from '../EntityCard'

function drag(el: Element, from: [number, number], to: [number, number]) {
  fireEvent.pointerDown(el, { clientX: from[0], clientY: from[1], pointerId: 1, pointerType: 'touch' })
  fireEvent.pointerMove(el, { clientX: to[0], clientY: to[1], pointerId: 1, pointerType: 'touch' })
  fireEvent.pointerUp(el, { clientX: to[0], clientY: to[1], pointerId: 1, pointerType: 'touch' })
}

describe('EntityCard — swipe-to-reveal excluir (mobile)', () => {
  beforeEach(() => {
    coarse = true
    reducedMotion = false
  })
  afterEach(cleanup)

  it('arrastar para a esquerda revela Excluir; tocar chama onSwipeDelete (não navega)', () => {
    const onClick = vi.fn()
    const onSwipeDelete = vi.fn()
    render(<EntityCard title="Célula A" onClick={onClick} onSwipeDelete={onSwipeDelete} />)

    const card = screen.getByRole('button', { name: 'Abrir Célula A' })
    drag(card, [200, 50], [110, 55]) // -90px horizontal, além do meio (48px)

    // painel revelado tem o botão "Excluir" (aria-hidden — buscamos por texto).
    const excluir = screen.getByText('Excluir')
    fireEvent.click(excluir)
    expect(onSwipeDelete).toHaveBeenCalledTimes(1)
    // o arrasto NÃO disparou a navegação do card.
    expect(onClick).not.toHaveBeenCalled()
  })

  it('arrasto vertical (rolagem) NÃO revela nem move o card', () => {
    const onSwipeDelete = vi.fn()
    render(<EntityCard title="Célula B" onClick={vi.fn()} onSwipeDelete={onSwipeDelete} />)
    const card = screen.getByRole('button', { name: 'Abrir Célula B' })

    drag(card, [200, 50], [196, 160]) // dy domina → rolagem
    const slider = card as HTMLElement
    expect(slider.style.transform).toBe('translateX(0px)')
  })

  it('um TAP (sem movimento) navega normalmente', () => {
    const onClick = vi.fn()
    render(<EntityCard title="Célula C" onClick={onClick} onSwipeDelete={vi.fn()} />)
    const card = screen.getByRole('button', { name: 'Abrir Célula C' })

    fireEvent.pointerDown(card, { clientX: 100, clientY: 50, pointerId: 1, pointerType: 'touch' })
    fireEvent.pointerUp(card, { clientX: 100, clientY: 50, pointerId: 1, pointerType: 'touch' })
    fireEvent.click(card)
    expect(onClick).toHaveBeenCalledTimes(1)
  })

  it('movimento reduzido: sem transição na revelação (instantâneo)', () => {
    reducedMotion = true
    render(<EntityCard title="Célula D" onClick={vi.fn()} onSwipeDelete={vi.fn()} />)
    const card = screen.getByRole('button', { name: 'Abrir Célula D' }) as HTMLElement

    drag(card, [200, 50], [110, 52])
    expect(card.style.transition).toBe('none')
  })

  it('sem ponteiro grosso (desktop) NÃO monta o gesto — estrutura clássica', () => {
    coarse = false
    const onSwipeDelete = vi.fn()
    render(<EntityCard title="Célula E" onClick={vi.fn()} onSwipeDelete={onSwipeDelete} />)
    // o painel de swipe não existe.
    expect(screen.queryByText('Excluir')).toBeNull()
  })
})
