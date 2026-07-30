import { create } from 'zustand'
import { createJSONStorage, persist } from 'zustand/middleware'
import { zustandStorage } from '../lib/safeStorage'

// internationalization D-I1/D-I6 — o idioma da UI. pt-BR é o PADRÃO na ausência de
// `rt-lang` (pedido do dono). Persistido em localStorage['rt-lang'], por dispositivo,
// espelho exato do `themeStore`. NÃO deriva de `navigator.language` (a escolha é
// explícita; o default fixo é pt-BR). Quando logado, o cliente sincroniza este valor
// com `users.locale` (G6) — a store segue sendo a fonte por dispositivo.
export type Lang = 'pt-BR' | 'en'

interface LanguageState {
  lang: Lang
  setLang: (lang: Lang) => void
}

export const useLanguageStore = create<LanguageState>()(
  persist(
    (set) => ({
      lang: 'pt-BR',
      setLang: (lang) => set({ lang }),
    }),
    {
      name: 'rt-lang',
      // Mesma degradação do tema (offline-pwa D7-11 / workspace-settings §4.2): storage
      // BLOQUEADO (modo privado) não derruba a troca — o adapter do safeStorage cai no
      // fallback de memória e o idioma vale só na sessão (o painel Aparência avisa).
      storage: createJSONStorage(() => zustandStorage('local')),
    },
  ),
)
