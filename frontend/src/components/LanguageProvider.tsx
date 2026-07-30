import React, { Fragment } from 'react'
import { useLanguage } from '@/hooks/useLanguage'

// internationalization D-I2 — espelho do `ThemeProvider`. Aplica o idioma e força o
// remount da árvore autenticada por `key={lang}` quando o idioma troca, para que toda
// tela releia os módulos `lib/i18n` no idioma novo (o cache do React Query vive fora
// da árvore e NÃO é refeito — os dados persistem, só os rótulos trocam).
interface LanguageProviderProps {
  children: React.ReactNode
}

export function LanguageProvider({ children }: LanguageProviderProps) {
  const { lang } = useLanguage()
  return <Fragment key={lang}>{children}</Fragment>
}
