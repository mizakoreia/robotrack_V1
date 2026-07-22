import { cn } from '@/lib/utils'
import { Icon } from '@/components/icons/Icon'
import type { BadgeStatus } from './Badge'

// design-system 6.2 (§5.2) — o StatusSelect é CONTROLE, não rótulo. `<select>`
// nativo com `appearance: none` e o chevron do sprite SEMPRE presente — não
// existe prop que o remova. MODO DE FALHA: um seletor de status indistinguível de
// um badge estático (mesma árvore) faz ninguém descobrir que a pílula é clicável.
// Por isso o chevron é obrigatório e a árvore é um `<div><select/><chevron/></div>`
// — nunca um `<span>` como o Badge. O chevron herda a tinta via `currentColor`.
export interface StatusOption {
  value: string
  label: string
}

export interface StatusSelectProps {
  value: string
  options: StatusOption[]
  onChange: (value: string) => void
  status?: BadgeStatus
  disabled?: boolean
  className?: string
  'aria-label'?: string
}

const INK: Record<BadgeStatus, string> = {
  success: 'text-success-ink',
  warning: 'text-warning-ink',
  danger: 'text-danger-ink',
  na: 'text-na-ink',
  accent: 'text-accent-ink',
}

export function StatusSelect({ value, options, onChange, status = 'na', disabled, className, ...aria }: StatusSelectProps) {
  return (
    <div className={cn('relative inline-flex items-center', INK[status], className)}>
      <select
        value={value}
        disabled={disabled}
        aria-label={aria['aria-label']}
        onChange={(e) => onChange(e.target.value)}
        className="label-md appearance-none rounded-pill border border-current/30 bg-transparent py-0.5 pl-2.5 pr-7 font-medium text-current"
      >
        {options.map((o) => (
          <option key={o.value} value={o.value}>
            {o.label}
          </option>
        ))}
      </select>
      {/* chevron obrigatório, não suprimível; pointer-events-none para o clique
          cair no <select>; herda a tinta do status por currentColor */}
      <span className="pointer-events-none absolute right-1.5 top-1/2 -translate-y-1/2">
        <Icon name="chevron-down" size="sm" />
      </span>
    </div>
  )
}
