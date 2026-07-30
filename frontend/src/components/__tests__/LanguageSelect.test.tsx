import { afterEach, describe, expect, it } from 'vitest'
import { render, screen, within, cleanup, fireEvent } from '@testing-library/react'
import { LanguageSelect } from '../LanguageSelect'
import { useLanguageStore } from '@/store/languageStore'

// internationalization D-I7 — o seletor é CONTROLE acessível com bandeira (não emoji).
// Prova: nome acessível = idioma (não a bandeira), dois alvos explícitos, troca o
// idioma no store, alvo de toque ≥40px, e a bandeira é decorativa (aria-hidden).
afterEach(() => {
  cleanup()
  useLanguageStore.setState({ lang: 'pt-BR' })
})

describe('LanguageSelect — menu', () => {
  it('o gatilho tem nome acessível bilíngue "Idioma / Language" (não a bandeira)', () => {
    render(<LanguageSelect />)
    const trigger = screen.getByRole('button', { name: 'Idioma / Language' })
    expect(trigger).toBeInTheDocument()
    // a bandeira é decorativa
    expect(trigger.querySelector('[aria-hidden="true"]')).toBeTruthy()
  })

  it('o alvo de toque é ≥40px (luva)', () => {
    render(<LanguageSelect />)
    const trigger = screen.getByRole('button', { name: 'Idioma / Language' })
    expect(trigger.className).toMatch(/min-h-\[40px\]/)
  })

  it('abre dois alvos explícitos e troca o idioma no store', () => {
    render(<LanguageSelect />)
    fireEvent.click(screen.getByRole('button', { name: 'Idioma / Language' }))
    const menu = screen.getByRole('menu')
    const items = within(menu).getAllByRole('menuitem')
    expect(items.map((i) => i.textContent)).toEqual(['Português (Brasil)', 'English (UK)'])
    fireEvent.click(within(menu).getByText('English (UK)'))
    expect(useLanguageStore.getState().lang).toBe('en')
  })
})

describe('LanguageSelect — segmented', () => {
  it('dois botões com aria-pressed refletindo o idioma atual', () => {
    render(<LanguageSelect layout="segmented" />)
    const group = screen.getByRole('group', { name: 'Idioma / Language' })
    const pt = within(group).getByRole('button', { name: /Português/ })
    const en = within(group).getByRole('button', { name: /English/ })
    expect(pt).toHaveAttribute('aria-pressed', 'true')
    expect(en).toHaveAttribute('aria-pressed', 'false')
    fireEvent.click(en)
    expect(useLanguageStore.getState().lang).toBe('en')
  })
})
