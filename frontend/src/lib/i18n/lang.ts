import { useLanguageStore, type Lang } from '@/store/languageStore'

// internationalization D-I2 — o idioma corrente como variável de módulo, para o
// `defineText` resolver a chave SINCRONAMENTE em código não-React (formatação,
// helpers) sem hook. A fonte durável é o `languageStore`; o `LanguageProvider`
// espelha as trocas aqui e força o remount da árvore (as telas releem `defineText`
// no idioma novo). Inicializa do store hidratado (o persist do zustand lê o
// localStorage de forma síncrona no load do módulo).
export type { Lang }

let currentLang: Lang = 'pt-BR'
try {
  currentLang = useLanguageStore.getState().lang
} catch {
  // store indisponível (ambiente sem storage) — mantém o default pt-BR.
}

export function getLang(): Lang {
  return currentLang
}

export function setLang(lang: Lang): void {
  currentLang = lang
}

// Tag BCP-47 para `Intl`/`toLocaleString`/`localeCompare` (D-I3). GB por decisão do
// dono (bandeira do Reino Unido). pt-BR permanece pt-BR.
export function localeTag(lang: Lang = currentLang): string {
  return lang === 'en' ? 'en-GB' : 'pt-BR'
}
