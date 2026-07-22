import { cn } from '@/lib/utils'

// design-system 5.3 (§5.2) — o hub analítico: rótulo pequeno sobre valor grande e
// uma barra de proporção. MODO DE FALHA: animar a `width` da barra recalcula
// layout a cada frame e engasga; a barra anima por `transform: scaleX()` com
// `transform-origin: left` (composição na GPU, sem relayout). `width` é 100%
// CONSTANTE. `role="progressbar"` + aria-valuenow/min/max para o leitor de tela.
export interface HubProps {
  label: string
  value: number // 0..100 — a proporção da barra
  valueText?: string // texto grande (ex.: "12/40"); default `${value}%`
  className?: string
}

export function Hub({ label, value, valueText, className }: HubProps) {
  const pct = Math.max(0, Math.min(100, Math.round(value)))

  return (
    <div className={cn('flex flex-col gap-1', className)}>
      <span className="label-sm text-text-muted">{label}</span>
      <span className="title tabular">{valueText ?? `${pct}%`}</span>
      <div
        role="progressbar"
        aria-valuenow={pct}
        aria-valuemin={0}
        aria-valuemax={100}
        className="bg-track mt-1 h-2 w-full overflow-hidden rounded-pill"
      >
        {/* width 100% fixa; a animação é só transform (scaleX), origin left */}
        <div
          className="bg-accent-solid h-full w-full origin-left transition-transform"
          style={{ transform: `scaleX(${pct / 100})` }}
        />
      </div>
    </div>
  )
}
