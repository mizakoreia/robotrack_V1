import React, { Fragment } from 'react'
import { useLanguage } from '@/hooks/useLanguage'
import { useAccountLocaleSync } from '@/hooks/useAccountLocaleSync'

// internationalization D-I2 — espelho do `ThemeProvider`. Aplica o idioma e força o
// remount da árvore autenticada por `key={lang}` quando o idioma troca, para que toda
// tela releia os módulos `lib/i18n` no idioma novo (o cache do React Query vive fora
// da árvore e NÃO é refeito — os dados persistem, só os rótulos trocam).
interface LanguageProviderProps {
  children: React.ReactNode
}

export function LanguageProvider({ children }: LanguageProviderProps) {
  const { lang } = useLanguage()
  // internationalization G6 — a sincronia conta↔dispositivo vive AQUI (no corpo do
  // provider, que persiste entre trocas de idioma; só a árvore-filha remonta pelo
  // `key`), então os refs de hidratação não se perdem a cada troca.
  useAccountLocaleSync()
  return <Fragment key={lang}>{children}</Fragment>
}
