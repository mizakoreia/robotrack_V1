import { describe, expect, it, afterEach } from 'vitest'
import { render, screen, cleanup, fireEvent } from '@testing-library/react'
import { createRef } from 'react'
import { Modal } from '../Modal'
import { Tooltip } from '../Tooltip'
import { PortalMenu } from '../../menu/PortalMenu'

afterEach(cleanup)

// impeccable-remediation G2 — verificação dos comportamentos NOVOS de harden que
// não tinham cobertura. Cada teste reprova a versão anterior a G2.
describe('G2 — Modal endurecido', () => {
  it('trava a rolagem do body enquanto aberto e a restaura ao fechar', () => {
    document.body.style.overflow = 'scroll' // valor anterior arbitrário
    const { rerender } = render(<Modal open onClose={() => {}} title="T">corpo</Modal>)
    expect(document.body.style.overflow).toBe('hidden')
    rerender(<Modal open={false} onClose={() => {}} title="T">corpo</Modal>)
    expect(document.body.style.overflow).toBe('scroll')
  })

  it('o × de fechar é um botão com nome acessível e alvo de toque (IconButton)', () => {
    render(<Modal open onClose={() => {}} title="T">corpo</Modal>)
    const close = screen.getByRole('button', { name: 'Fechar' })
    // IconButton size="sm" → h-8 w-8 (32px)
    expect(close.className).toMatch(/h-8/)
    expect(close.tagName).toBe('BUTTON')
  })

  it('o corpo tem container com rolagem interna (não estoura o viewport)', () => {
    render(<Modal open onClose={() => {}} title="T"><p>corpo</p></Modal>)
    const dialog = screen.getByRole('dialog', { name: 'T' })
    expect(dialog.className).toMatch(/max-h-\[90vh\]/)
    expect(dialog.querySelector('.overflow-y-auto')).not.toBeNull()
  })
})

describe('G2 — Tooltip acessível', () => {
  it('associa o conteúdo por aria-describedby e revela por foco; Esc dispensa', () => {
    render(
      <Tooltip content="ajuda">
        <button>alvo</button>
      </Tooltip>,
    )
    const wrapper = screen.getByText('alvo').parentElement as HTMLElement
    const descId = wrapper.getAttribute('aria-describedby')
    expect(descId).toBeTruthy()
    const tip = document.getElementById(descId as string) as HTMLElement
    expect(tip.getAttribute('role')).toBe('tooltip')
    // fechado por padrão
    expect(tip.className).toMatch(/opacity-0/)
    // abre por foco de teclado
    fireEvent.focus(wrapper)
    expect(tip.className).toMatch(/opacity-100/)
    // Esc dispensa
    fireEvent.keyDown(wrapper, { key: 'Escape' })
    expect(tip.className).toMatch(/opacity-0/)
  })
})

describe('G2 — PortalMenu navegável por teclado', () => {
  it('move o foco para o menu ao abrir (setas passam a operar)', () => {
    const anchor = createRef<HTMLButtonElement>()
    render(
      <>
        <button ref={anchor}>abrir</button>
        <PortalMenu
          anchorRef={anchor}
          open
          onClose={() => {}}
          label="Menu"
          items={[
            { label: 'Um', onSelect: () => {} },
            { label: 'Dois', onSelect: () => {} },
          ]}
        />
      </>,
    )
    const menu = screen.getByRole('menu', { name: 'Menu' })
    expect(document.activeElement).toBe(menu)
  })
})
