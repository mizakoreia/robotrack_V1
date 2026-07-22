import { useEffect, useState } from 'react'

// Hook de media query (robot-task-table 6.1) — renderiza UM layout por vez (tabela
// vs cartões), não os dois escondidos por CSS. Além de evitar montar duas árvores
// (importa para a contagem de render de §7.1), mantém o DOM limpo para leitores de
// tela. Quando `matchMedia` não existe (jsdom sem polyfill), assume `fallback`
// (desktop por padrão) — os testes que querem o mobile injetam `window.matchMedia`.
export function useMediaQuery(query: string, fallback = true): boolean {
  const read = () =>
    typeof window !== 'undefined' && typeof window.matchMedia === 'function'
      ? window.matchMedia(query).matches
      : fallback

  const [matches, setMatches] = useState(read)

  useEffect(() => {
    if (typeof window === 'undefined' || typeof window.matchMedia !== 'function') return
    const mql = window.matchMedia(query)
    const onChange = () => setMatches(mql.matches)
    onChange()
    mql.addEventListener('change', onChange)
    return () => mql.removeEventListener('change', onChange)
  }, [query])

  return matches
}
