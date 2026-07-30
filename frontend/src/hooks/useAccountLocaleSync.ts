import { useEffect, useRef } from 'react'
import { useLanguageStore } from '@/store/languageStore'
import { useAuthStore } from '@/store/authStore'
import { apiClient } from '@/lib/api/client'

// internationalization G6 (D-I6) — sincroniza a preferência de idioma entre o
// dispositivo (`rt-lang`) e a CONTA (`users.locale`). Dois sentidos:
//   1. HIDRATA: ao entrar (o usuário aparece), adota o `locale` da conta — assim a
//      preferência segue a pessoa entre dispositivos. Uma vez por login (por `id`).
//   2. PERSISTE: quando a pessoa TROCA o idioma no seletor estando logada, grava na
//      conta (`PATCH /auth/v1/me`) e atualiza o store — sem laço (após hidratar,
//      `lang === user.locale`, então o efeito de persistir não dispara).
export function useAccountLocaleSync() {
  const lang = useLanguageStore((s) => s.lang)
  const setLang = useLanguageStore((s) => s.setLang)
  const user = useAuthStore((s) => s.user)
  const setUser = useAuthStore((s) => s.setUser)
  const hydratedFor = useRef<string | null>(null)

  // 1. HIDRATA do locale da conta, uma vez por login.
  useEffect(() => {
    if (!user?.id) {
      hydratedFor.current = null
      return
    }
    if (hydratedFor.current === user.id) return
    hydratedFor.current = user.id
    if (user.locale && user.locale !== lang) setLang(user.locale)
    // `lang` fora das deps de propósito: hidrata pela IDENTIDADE do usuário, não a
    // cada troca de idioma (a persistência abaixo cuida das trocas).
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [user?.id, user?.locale, setLang])

  // 2. PERSISTE a troca do usuário logado na conta.
  useEffect(() => {
    if (!user?.id) return
    if (user.locale === lang) return
    let cancelled = false
    apiClient
      .patch('/auth/v1/me', { locale: lang })
      .then(() => {
        if (!cancelled) setUser({ ...user, locale: lang })
      })
      .catch(() => {
        // best-effort: o dispositivo já está no idioma novo; a conta sincroniza na
        // próxima troca/entrada. Não bloqueia a UI nem derruba nada.
      })
    return () => {
      cancelled = true
    }
  }, [lang, user, setUser])
}
