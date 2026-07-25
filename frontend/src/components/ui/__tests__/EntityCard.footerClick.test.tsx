import { describe, it, expect, vi, afterEach } from 'vitest'
import { render, screen, fireEvent, cleanup } from '@testing-library/react'

// owner-only-card-delete — REGRESSÃO "a lixeira não exclui no desktop". O card
// inteiro navega (role=button), mas um clique que nasce num controle do rodapé
// (editar/excluir) NÃO deve navegar. O alvo real do clique costuma ser o <svg> do
// ícone dentro do botão — e SVGElement NÃO é HTMLElement. O guarda antigo
// (`target instanceof HTMLElement`) descartava esse clique como "não-interno",
// então o card NAVEGAVA em vez de deixar o botão excluir agir. Com o gesto
// desligado (ponteiro fino/desktop) só existe o caminho clássico — é onde o dono
// bateu. Estes três níveis (projeto/célula/robô) usam o MESMO EntityCard, então
// este guarda vale para os três.
vi.mock('@/lib/useMediaQuery', () => ({
  useMediaQuery: (query: string, fallback = false) => {
    if (query.includes('pointer: coarse')) return false // desktop: sem swipe
    if (query.includes('prefers-reduced-motion')) return false
    return fallback
  },
}))

import { EntityCard } from '../EntityCard'
import { IconButton } from '../IconButton'

afterEach(cleanup)

describe('EntityCard — clique no rodapé (desktop) não engole no card', () => {
  it('clicar no ÍCONE (svg) do botão do rodapé chama o handler do botão e NÃO navega', () => {
    const onNavigate = vi.fn()
    const onDelete = vi.fn()
    render(
      <EntityCard
        title="Projeto X"
        onClick={onNavigate}
        footer={<IconButton icon="trash" label="Excluir Projeto X" onClick={onDelete} />}
      />,
    )

    const botao = screen.getByRole('button', { name: 'Excluir Projeto X' })
    // o glifo preenche quase todo o alvo — o alvo real do clique é o <svg>.
    const svg = botao.querySelector('svg')
    expect(svg).not.toBeNull()
    fireEvent.click(svg as Element)

    expect(onDelete).toHaveBeenCalledTimes(1)
    // o clique no botão do rodapé NÃO disparou a navegação do card.
    expect(onNavigate).not.toHaveBeenCalled()
  })

  it('clicar no CORPO do card navega normalmente', () => {
    const onNavigate = vi.fn()
    render(<EntityCard title="Projeto Y" onClick={onNavigate} />)

    fireEvent.click(screen.getByRole('button', { name: 'Abrir Projeto Y' }))
    expect(onNavigate).toHaveBeenCalledTimes(1)
  })
})
