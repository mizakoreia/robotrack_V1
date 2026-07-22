import { cn } from '@/lib/utils'
import { Icon } from '@/components/icons/Icon'

// design-system 6.3 (§5.2) — chip de responsável/contribuinte/tag. ESTÁTICO por
// padrão (um `<span>`, não focável). A variante removível ganha um `<button>` com
// `aria-label` contendo o nome e alvo ≥ 32×32px. MODO DE FALHA: um chip não
// removível que receba foco por Tab transforma uma lista de 12 responsáveis em 12
// paradas mortas na navegação por teclado — por isso o `<span>` não é focável e só
// a variante removível introduz um alvo de foco (o botão de remover).
export interface ChipProps {
  label: string
  onRemove?: () => void
  className?: string
}

export function Chip({ label, onRemove, className }: ChipProps) {
  return (
    <span
      className={cn(
        'label-md bg-bg-sunken inline-flex items-center gap-1 rounded-pill py-1 pl-2.5 font-medium',
        onRemove ? 'pr-1' : 'pr-2.5',
        className,
      )}
    >
      {label}
      {onRemove && (
        <button
          type="button"
          aria-label={`Remover ${label}`}
          onClick={onRemove}
          className="grid h-8 w-8 place-content-center rounded-pill text-text-muted hover:text-text-main"
        >
          <Icon name="close" size="sm" />
        </button>
      )}
    </span>
  )
}
