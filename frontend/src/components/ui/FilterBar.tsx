import { cn } from '@/lib/utils'

// design-system 6.6 (§5.2) — barra de filtro segmentada em pílula. O segmento
// ATIVO usa `bg-accent-solid` + branco (#1d4ed8 = 6.70:1 com branco, passa AA).
// MODO DE FALHA: usar `bg-accent` (#3b82f6 = 3.68:1) reprova AA — por isso o ativo
// é a variante SÓLIDA, não a cheia. `role="tab"` + `aria-selected`, altura ≥ 32px.
export interface FilterOption {
  value: string
  label: string
}

export interface FilterBarProps {
  options: FilterOption[]
  value: string
  onChange: (value: string) => void
  className?: string
  'aria-label'?: string
}

export function FilterBar({ options, value, onChange, className, ...aria }: FilterBarProps) {
  return (
    <div role="tablist" aria-label={aria['aria-label']} className={cn('bg-bg-sunken inline-flex gap-0.5 rounded-pill p-0.5', className)}>
      {options.map((o) => {
        const active = o.value === value
        return (
          <button
            key={o.value}
            type="button"
            role="tab"
            aria-selected={active}
            onClick={() => onChange(o.value)}
            className={cn(
              'label-md h-8 rounded-pill px-3 font-medium transition-colors',
              active ? 'bg-accent-solid text-white' : 'text-text-muted hover:text-text-main',
            )}
          >
            {o.label}
          </button>
        )
      })}
    </div>
  )
}
