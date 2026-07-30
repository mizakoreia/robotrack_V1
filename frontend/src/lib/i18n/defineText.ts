import { getLang } from './lang'

// internationalization D-I2 — o eixo de idioma dos módulos de texto. Cada módulo
// exporta `defineText(ptBR, en)` mantendo O MESMO NOME de export de hoje, então os
// ~29 arquivos consumidores (`inviteText.foo`, `advanceText.bar`) NÃO mudam uma linha.
//
// É um Proxy sobre o mapa pt-BR:
//   - `get(chave)` devolve o valor do IDIOMA CORRENTE (pt-BR por padrão; en quando
//     trocado). Vale para string, função (plural/interpolação) e sub-objeto aninhado
//     (ex.: `progressText.metrics.weighted.label`) — o sub-objeto inteiro vem do
//     idioma corrente.
//   - a ENUMERAÇÃO (`ownKeys`/descriptors) usa o alvo pt-BR, então
//     `Object.values(inviteText)` continua devolvendo os literais pt-BR no default —
//     é o que os sweeps D14 (`*.i18n.test.ts`) e a regra G leem. Trocar o idioma no
//     runtime não muda a forma, só os valores.
//
// A reatividade em React vem do remount por `key={lang}` no `LanguageProvider`
// (D-I2) — trocar idioma é raro e um re-render completo é aceitável e correto.
export function defineText<T extends object>(ptBR: T, en: T): T {
  return new Proxy(ptBR, {
    get(target, prop, receiver) {
      const source = getLang() === 'en' ? (en as object) : (target as object)
      return Reflect.get(source, prop, receiver)
    },
  }) as T
}
