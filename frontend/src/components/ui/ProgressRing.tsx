import { cn } from '@/lib/utils'

// design-system 5.2 (§5.2) — o anel de progresso, primitivo BASE (sem métrica; o
// envelope rotulado D15 é `features`/`progress`). MODO DE FALHA que este código
// existe para evitar: desenhar o path de progresso a 0% com `stroke-dasharray: 0`
// + `stroke-linecap: round` produz um PONTO arredondado que sugere avanço
// inexistente. Por isso o path de progresso é OMITIDO quando `value === 0` — o
// DOM a 0% contém só o trilho. Omitir NÃO é o mesmo que zerar.
export interface ProgressRingProps {
  value: number
  size?: number
  /** Sobrescreve o aria-label (o wrapper de métrica passa "<rótulo>: 58%"). */
  label?: string
  className?: string
}

export function ProgressRing({ value, size = 64, label, className }: ProgressRingProps) {
  const v = Math.max(0, Math.min(100, Math.round(value)))

  return (
    <div
      role="img"
      aria-label={label ?? `${v}%`}
      style={{ width: size, height: size }}
      className={cn('relative inline-flex items-center justify-center', className)}
    >
      <svg viewBox="0 0 36 36" className="h-full w-full -rotate-90">
        <circle cx="18" cy="18" r="15.9155" fill="none" className="stroke-track" strokeWidth="3" />
        {v > 0 && (
          <circle
            cx="18"
            cy="18"
            r="15.9155"
            fill="none"
            className="stroke-accent"
            strokeWidth="3"
            strokeDasharray={`${v}, 100`}
            strokeLinecap="round"
          />
        )}
      </svg>
      <span aria-hidden="true" className="tabular absolute text-sm font-medium">
        {v}%
      </span>
    </div>
  )
}
