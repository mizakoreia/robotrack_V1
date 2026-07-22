import { create } from 'zustand'
import { persist } from 'zustand/middleware'

// design-system 4.2 (§5.1, D-DS-3) — o tema. Escuro é o PADRÃO na ausência de
// `rt-theme` (o modo primário §5.1, o melhor sob luz de galpão); o claro só entra
// quando a pessoa pede. Persistido em localStorage['rt-theme']. O tema NÃO deriva
// do esquema do sistema operacional — a decisão de produto é protegida pelo
// guarda de 4.3.
interface ThemeState {
  theme: 'light' | 'dark'
  toggleTheme: () => void
  setTheme: (theme: 'light' | 'dark') => void
}

export const useThemeStore = create<ThemeState>()(
  persist(
    (set) => ({
      theme: 'dark',
      toggleTheme: () => set((state) => ({ theme: state.theme === 'dark' ? 'light' : 'dark' })),
      setTheme: (theme) => set({ theme }),
    }),
    {
      name: 'rt-theme',
    },
  ),
)
