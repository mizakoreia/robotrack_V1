import type { LanguageText } from './language'

// internationalization D-I7 — EN do seletor. Endônimos e o aria bilíngue são
// idênticos; só o chrome localizável muda.
export const languageTextEn: LanguageText = {
  triggerAria: 'Idioma / Language',
  menuLabel: 'Choose language',
  short: { 'pt-BR': 'PT', en: 'EN' },
  option: { 'pt-BR': 'Português (Brasil)', en: 'English (UK)' },
  panelLabel: 'Language',
  panelHint: 'This choice applies to this device only.',
}
