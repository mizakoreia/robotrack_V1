import { create } from 'zustand'
import { createJSONStorage, persist } from 'zustand/middleware'
import { zustandStorage } from '../lib/safeStorage'

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
      // workspace-settings 6.1 (§4.2) + offline-pwa D7-11 — armazenamento
      // BLOQUEADO (modo privado) não pode derrubar o toggle: o persist do zustand
      // NÃO captura o throw do setItem. O adapter do safeStorage degrada em
      // silêncio (fallback de memória) — o tema troca na sessão e a preferência
      // simplesmente não é lembrada (o painel Aparência avisa). Um único caminho
      // de storage, sem `window.localStorage` solto.
      storage: createJSONStorage(() => zustandStorage('local')),
    },
  ),
)
