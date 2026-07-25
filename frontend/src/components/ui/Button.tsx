import * as React from 'react'
import { cn } from '@/lib/utils'

export interface ButtonProps
  extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  // impeccable-remediation G5 — variantes banidas `primary` e `gradient` (texto/
  // fundo em gradiente) REMOVIDAS do union: não tinham uso no produto e passá-las
  // agora é erro de tsc. `uiverse` (skin `.btn` de borda animada) permanece só
  // porque a LANDING de marketing (components/campfire/*) depende dele — nenhum
  // callsite do PRODUTO usa; removê-lo é restilizar a landing, fora deste escopo
  // (ver design-system EXECUCAO decisão 4).
  variant?: 'default' | 'destructive' | 'outline' | 'secondary' | 'ghost' | 'link' | 'uiverse'
  size?: 'default' | 'sm' | 'lg' | 'icon'
}

const Button = React.forwardRef<HTMLButtonElement, ButtonProps>(
  ({ className, variant = 'default', size = 'default', ...props }, ref) => {
    const baseStyles = 'inline-flex items-center justify-center whitespace-nowrap font-medium ring-offset-background transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 disabled:pointer-events-none disabled:opacity-50'
    
    const variants = {
      // impeccable-remediation G1 (§DESIGN regra dura) — a variante SÓLIDA é a única
      // forma AA de branco sobre a cor: `--accent-solid` #1d4ed8 = 6,70:1 (o antigo
      // `bg-primary` #3b82f6 dava 3,68:1 e reprovava corpo). Hover por `brightness`
      // porque o `/opacity` não compõe sobre `hsl(var(--x))` sem canal alfa (Tw 3.3).
      default: 'bg-accent-solid text-white hover:brightness-110',
      destructive: 'bg-danger-solid text-white hover:brightness-110',
      outline: 'border border-input bg-background hover:bg-accent hover:text-accent-foreground',
      secondary: 'bg-secondary text-secondary-foreground hover:bg-secondary/80',
      ghost: 'hover:bg-accent hover:text-accent-foreground',
      link: 'text-primary underline-offset-4 hover:underline',
      uiverse: ''
    }
    
    const sizes = {
      default: 'h-10 px-4 py-2',
      sm: 'h-9 rounded-md px-3',
      lg: 'h-11 rounded-md px-8',
      icon: 'h-10 w-10'
    }

    if (variant === 'uiverse') {
      return (
        <button
          className={cn('btn', className)}
          ref={ref}
          {...props}
        />
      )
    }

    return (
      <button
        className={cn(baseStyles, variants[variant], sizes[size], className)}
        ref={ref}
        {...props}
      />
    )
  }
)
Button.displayName = 'Button'

export { Button }