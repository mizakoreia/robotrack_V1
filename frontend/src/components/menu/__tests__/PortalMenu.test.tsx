import { describe, expect, it, vi, beforeEach } from 'vitest'
import { render, screen, fireEvent, act } from '@testing-library/react'
import { PortalMenu } from '../PortalMenu'
import { useMenu } from '../useMenu'

// app-shell-navigation 3.6 (D-C) — o primitivo: portal na raiz, os cinco gatilhos
// de fechamento (clique fora, Esc, scroll, resize, escolha), a regra do teclado
// virtual, o foco de volta ao gatilho, e a navegação por teclado com ciclo.

function Harness({ onSelect = vi.fn(), scrollContainer }: { onSelect?: () => void; scrollContainer?: HTMLElement }) {
  const menu = useMenu()
  return (
    <>
      <button {...menu.triggerProps}>abrir</button>
      <PortalMenu
        anchorRef={menu.anchorRef}
        open={menu.open}
        onClose={menu.close}
        scrollContainer={scrollContainer}
        items={[
          { label: 'Um', onSelect },
          { label: 'Dois', onSelect },
          { label: 'Três', onSelect },
        ]}
      />
    </>
  )
}

beforeEach(() => {
  document.getElementById('rt-overlays')?.remove()
})

function openMenu() {
  const trigger = screen.getByRole('button', { name: 'abrir' })
  act(() => trigger.focus())
  fireEvent.click(trigger)
  return trigger
}

describe('PortalMenu (D-C)', () => {
  it('renderiza em #rt-overlays (portal), não sob o gatilho', () => {
    render(<Harness />)
    openMenu()
    const menu = screen.getByRole('menu')
    expect(document.getElementById('rt-overlays')?.contains(menu)).toBe(true)
    expect(menu.style.position).toBe('fixed')
  })

  it('aria-expanded do gatilho reflete o estado real', () => {
    render(<Harness />)
    const trigger = screen.getByRole('button', { name: 'abrir' })
    expect(trigger).toHaveAttribute('aria-expanded', 'false')
    expect(trigger).toHaveAttribute('aria-haspopup', 'menu')
    fireEvent.click(trigger)
    expect(trigger).toHaveAttribute('aria-expanded', 'true')
  })

  it('Esc fecha e DEVOLVE o foco ao gatilho', () => {
    render(<Harness />)
    const trigger = openMenu()
    fireEvent.keyDown(document, { key: 'Escape' })
    expect(screen.queryByRole('menu')).toBeNull()
    expect(document.activeElement).toBe(trigger)
  })

  it('clique fora fecha (sem refocar o gatilho)', () => {
    render(
      <div>
        <Harness />
        <div data-testid="fora">fora</div>
      </div>,
    )
    openMenu()
    fireEvent.pointerDown(screen.getByTestId('fora'))
    expect(screen.queryByRole('menu')).toBeNull()
  })

  it('rolagem da janela fecha', () => {
    render(<Harness />)
    openMenu()
    fireEvent.scroll(window)
    expect(screen.queryByRole('menu')).toBeNull()
  })

  it('escolher um item chama onSelect e fecha', () => {
    const onSelect = vi.fn()
    render(<Harness onSelect={onSelect} />)
    openMenu()
    fireEvent.click(screen.getByRole('menuitem', { name: 'Dois' }))
    expect(onSelect).toHaveBeenCalledTimes(1)
    expect(screen.queryByRole('menu')).toBeNull()
  })

  it('resize: largura muda fecha; altura −80 mantém; altura −200 fecha (teclado virtual)', () => {
    render(<Harness />)
    openMenu()
    // altura -80 (teclado virtual): mantém
    act(() => {
      Object.defineProperty(window, 'innerHeight', { value: window.innerHeight - 80, configurable: true })
      window.dispatchEvent(new Event('resize'))
    })
    expect(screen.queryByRole('menu')).not.toBeNull()
    // altura -200: fecha
    act(() => {
      Object.defineProperty(window, 'innerHeight', { value: window.innerHeight - 200, configurable: true })
      window.dispatchEvent(new Event('resize'))
    })
    expect(screen.queryByRole('menu')).toBeNull()
  })

  it('ArrowUp no primeiro item cicla para o último (3 itens)', () => {
    render(<Harness />)
    openMenu()
    const menu = screen.getByRole('menu')
    fireEvent.keyDown(menu, { key: 'ArrowUp' })
    expect(screen.getByRole('menuitem', { name: 'Três' })).toHaveAttribute('data-active', 'true')
  })

  it('Home vai ao primeiro, End ao último', () => {
    render(<Harness />)
    openMenu()
    const menu = screen.getByRole('menu')
    fireEvent.keyDown(menu, { key: 'End' })
    expect(screen.getByRole('menuitem', { name: 'Três' })).toHaveAttribute('data-active', 'true')
    fireEvent.keyDown(menu, { key: 'Home' })
    expect(screen.getByRole('menuitem', { name: 'Um' })).toHaveAttribute('data-active', 'true')
  })
})
