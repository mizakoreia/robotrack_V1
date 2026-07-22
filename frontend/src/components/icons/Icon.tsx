import { cn } from '@/lib/utils'
import type { IconName } from './sprite'

// design-system 3.2 (D-DS-8) — o componente Icon. Três tamanhos (18/15/22px),
// `aria-hidden` por padrão (o ícone é decorativo; o nome acessível vem do
// controle que o contém). Herda a cor por `currentColor` — nunca recebe prop de
// cor. Um `<Icon>` dentro de um `<button>` só-ícone NÃO dá nome acessível: é o
// `aria-label` do botão que dá (verificado no teste de tipo de 6.7).
const SIZES = { sm: 15, md: 18, lg: 22 } as const

export interface IconProps {
  name: IconName
  size?: keyof typeof SIZES
  className?: string
  title?: string // quando presente, o ícone deixa de ser aria-hidden e ganha nome
}

export function Icon({ name, size = 'md', className, title }: IconProps) {
  const px = SIZES[size]
  return (
    <svg
      width={px}
      height={px}
      className={cn('inline-block shrink-0', className)}
      aria-hidden={title ? undefined : true}
      role={title ? 'img' : undefined}
      aria-label={title}
      focusable="false"
    >
      <use href={`#i-${name}`} />
    </svg>
  )
}
