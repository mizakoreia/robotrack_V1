import * as React from 'react'
import { cn } from '@/lib/utils'
import { Icon } from '@/components/icons/Icon'
import type { IconName } from '@/components/icons/sprite'

// design-system 6.7 (D-DS-9) — a acessibilidade como ASSINATURA DE TIPO, não
// convenção. Um botão só-ícone SEM nome acessível é o defeito mais comum e o mais
// invisível numa revisão visual. Aqui `label` é OBRIGATÓRIO (vira `aria-label`):
// `<IconButton icon="trash" />` sem `label` é erro de `tsc --noEmit`, não um bug
// que só aparece com leitor de tela. Alvo ≥ 32×32px.
export interface IconButtonProps extends Omit<React.ButtonHTMLAttributes<HTMLButtonElement>, 'aria-label'> {
  icon: IconName
  label: string // obrigatório — sem default
  size?: 'sm' | 'md' | 'lg'
}

const BOX = { sm: 'h-8 w-8', md: 'h-9 w-9', lg: 'h-10 w-10' } as const

export const IconButton = React.forwardRef<HTMLButtonElement, IconButtonProps>(
  ({ icon, label, size = 'md', className, ...props }, ref) => (
    <button
      ref={ref}
      type="button"
      aria-label={label}
      className={cn(
        'grid place-content-center rounded-md text-text-muted transition-colors hover:text-text-main focus-visible:ring-2 focus-visible:ring-accent',
        BOX[size],
        className,
      )}
      {...props}
    >
      <Icon name={icon} size={size === 'lg' ? 'lg' : 'md'} />
    </button>
  ),
)
IconButton.displayName = 'IconButton'
