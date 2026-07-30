import { defineText } from './defineText'
import { languageTextEn } from './language.en'

// internationalization D-I7 — textos do seletor de idioma. Os NOMES dos idiomas são
// endônimos (iguais em qualquer UI): "Português (Brasil)" / "English (UK)". O rótulo
// acessível do gatilho é BILÍNGUE de propósito ("Idioma / Language") para ser
// descoberto em qualquer idioma (pedido do dono). O código curto (PT/EN) é o texto
// visível ao lado da bandeira, para legibilidade de galpão.
const languageTextPtBR = {
  // aria-label do gatilho — bilíngue, não localizado (achável nos dois idiomas)
  triggerAria: 'Idioma / Language',
  // título do grupo/menu
  menuLabel: 'Escolher idioma',
  // rótulo curto do gatilho por idioma
  short: { 'pt-BR': 'PT', en: 'EN' },
  // nomes das opções (endônimos — idênticos nos dois idiomas)
  option: { 'pt-BR': 'Português (Brasil)', en: 'English (UK)' },
  // rótulo do controle no painel Aparência
  panelLabel: 'Idioma',
  panelHint: 'A escolha vale só para este dispositivo.',
}

export type LanguageText = typeof languageTextPtBR
export const languageText: LanguageText = defineText(languageTextPtBR, languageTextEn)
