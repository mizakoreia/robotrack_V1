import { describe, expect, it, beforeEach } from 'vitest'
import { act, renderHook } from '@testing-library/react'
import { useTheme } from '../useTheme'
import { useThemeStore } from '@/store/themeStore'

// design-system 4.2 (D-DS-3) — o tema padrão é ESCURO, o claro adiciona `.light`
// na raiz, e a barra do navegador (`theme-color`) acompanha. Primeiro acesso num
// dispositivo com sistema em claro abre no ESCURO (não segue o sistema).

describe('useTheme (D-DS-3)', () => {
  beforeEach(() => {
    localStorage.clear()
    document.documentElement.className = ''
    let meta = document.querySelector('meta[name="theme-color"]')
    if (!meta) {
      meta = document.createElement('meta')
      meta.setAttribute('name', 'theme-color')
      document.head.appendChild(meta)
    }
    act(() => useThemeStore.setState({ theme: 'dark' }))
  })

  it('o padrão é escuro: sem classe .light, meta #0a0f1d', () => {
    renderHook(() => useTheme())
    expect(document.documentElement.classList.contains('light')).toBe(false)
    expect(document.documentElement.getAttribute('data-theme')).toBe('dark')
    expect(document.querySelector('meta[name="theme-color"]')?.getAttribute('content')).toBe('#0a0f1d')
  })

  it('claro adiciona .light e pinta a barra de #f1f5f9', () => {
    const { result } = renderHook(() => useTheme())
    act(() => result.current.setTheme('light'))
    expect(document.documentElement.classList.contains('light')).toBe(true)
    expect(document.querySelector('meta[name="theme-color"]')?.getAttribute('content')).toBe('#f1f5f9')
  })

  it('toggle a partir do escuro vai para o claro', () => {
    const { result } = renderHook(() => useTheme())
    act(() => result.current.toggleTheme())
    expect(useThemeStore.getState().theme).toBe('light')
  })
})
