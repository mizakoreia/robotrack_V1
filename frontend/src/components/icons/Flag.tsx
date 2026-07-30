// internationalization D-I7 — bandeiras BR / GB como SVG (NUNCA emoji: o
// `no-emoji.test.ts` reprova as bandeiras emoji — pares regional-indicator com
// `Emoji_Presentation`). São o ÚNICO glifo colorido do produto — exceção deliberada
// ao sprite monocromático (`currentColor`): uma bandeira tem cor própria e não pode
// herdar a tinta. É DECORATIVA (`aria-hidden`): o nome acessível do controle é o
// idioma, não a bandeira (D-I7). O contorno arredondado + `overflow-hidden` contêm os
// traços diagonais da Union Jack.

export type FlagCountry = 'BR' | 'GB'

interface FlagProps {
  country: FlagCountry
  className?: string
}

export function Flag({ country, className }: FlagProps) {
  return (
    <span
      aria-hidden="true"
      className={className}
      style={{
        display: 'inline-block',
        width: '1.4em',
        height: '1em',
        borderRadius: '2px',
        overflow: 'hidden',
        boxShadow: '0 0 0 1px rgba(0,0,0,0.15)',
        lineHeight: 0,
        flex: 'none',
      }}
    >
      {country === 'BR' ? <BrazilFlag /> : <UnionJack />}
    </span>
  )
}

function BrazilFlag() {
  return (
    <svg viewBox="0 0 28 20" width="100%" height="100%" preserveAspectRatio="none" focusable="false">
      <rect width="28" height="20" fill="#009B3A" />
      <path d="M14 2 25 10 14 18 3 10Z" fill="#FEDF00" />
      <circle cx="14" cy="10" r="4" fill="#002776" />
    </svg>
  )
}

function UnionJack() {
  return (
    <svg viewBox="0 0 28 20" width="100%" height="100%" preserveAspectRatio="none" focusable="false">
      <rect width="28" height="20" fill="#012169" />
      {/* saltire (diagonais) branca e vermelha */}
      <path d="M0 0 28 20M28 0 0 20" stroke="#FFFFFF" strokeWidth="4" />
      <path d="M0 0 28 20M28 0 0 20" stroke="#C8102E" strokeWidth="2" />
      {/* cruz de São Jorge branca e vermelha */}
      <path d="M14 0V20M0 10H28" stroke="#FFFFFF" strokeWidth="6" />
      <path d="M14 0V20M0 10H28" stroke="#C8102E" strokeWidth="3.4" />
    </svg>
  )
}
