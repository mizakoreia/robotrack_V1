import type { ReactNode } from 'react'
import { cn } from '@/lib/utils'

// design-system 6.1 (§5.2) — o Badge é RÓTULO, não controle. Pílula ESTÁTICA:
// fundo na variante cheia com o alpha do papel, texto na tinta. SEM prop
// `chevron`, SEM `onClick`, não focável. A interface NÃO estende
// HTMLAttributes<button> de propósito: passar `onClick` é erro de `tsc --noEmit`
// — um badge clicável é o começo da confusão que a regra "badge é rótulo,
// seletor é controle" (StatusSelect) existe para evitar.
export type BadgeStatus = 'success' | 'warning' | 'danger' | 'accent' | 'na'

export interface BadgeProps {
  status: BadgeStatus
  children: ReactNode
  className?: string
}

const BG: Record<BadgeStatus, string> = {
  success: 'bg-success/15',
  warning: 'bg-warning/15',
  danger: 'bg-danger/15',
  na: 'bg-na/15',
  accent: 'bg-accent/15',
}
const INK: Record<BadgeStatus, string> = {
  success: 'text-success-ink',
  warning: 'text-warning-ink',
  danger: 'text-danger-ink',
  na: 'text-na-ink',
  accent: 'text-accent-ink',
}

export function Badge({ status, children, className }: BadgeProps) {
  return (
    <span className={cn('label-md inline-flex items-center rounded-pill px-2 py-0.5 font-medium', BG[status], INK[status], className)}>
      {children}
    </span>
  )
}
