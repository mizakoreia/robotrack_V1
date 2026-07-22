import { useEffect } from 'react'
import { useThemeStore } from '@/store/themeStore'

// design-system 4.2 (D-DS-3) — aplica o tema. Escuro é o :root (sem classe); o
// claro adiciona `.light` na raiz. Sincroniza `<meta name="theme-color">` para a
// barra do navegador acompanhar. NÃO lê o esquema do sistema (guarda de 4.3).
const THEME_COLOR = { dark: '#0a0f1d', light: '#f1f5f9' } as const

export function useTheme() {
  const { theme, setTheme } = useThemeStore()

  useEffect(() => {
    const root = document.documentElement
    root.classList.toggle('light', theme === 'light')
    root.setAttribute('data-theme', theme)
    document.querySelector('meta[name="theme-color"]')?.setAttribute('content', THEME_COLOR[theme])
  }, [theme])

  const toggleTheme = () => setTheme(theme === 'dark' ? 'light' : 'dark')

  return { theme, toggleTheme, setTheme }
}
