import { useEffect } from 'react'
import { useLanguageStore, type Lang } from '@/store/languageStore'
import { setLang as setModuleLang } from '@/lib/i18n/lang'

// internationalization D-I2/D-I7 — aplica o idioma. Espelho do `useTheme`. Mantém a
// variável de módulo `currentLang` (lida pelo `defineText`) e o `<html lang>` em
// sincronia com o store. NÃO deriva de `navigator.language` — a escolha é do usuário,
// o default é pt-BR (guarda no store).
export function useLanguage() {
  const { lang, setLang } = useLanguageStore()

  // Sincroniza a variável de módulo já na renderização (antes das telas lerem o
  // `defineText`); o remount por `key={lang}` no provider garante a releitura.
  setModuleLang(lang)

  useEffect(() => {
    document.documentElement.lang = lang
  }, [lang])

  return { lang, setLang }
}

export type { Lang }
