// Componente de KPI Card estilizado
// Renderiza título, valor, variação (%), ícone com chip colorido e decoração ondulada
import React from 'react'

type IconType = React.ComponentType<React.SVGProps<SVGSVGElement>>

export function KpiCard({
  title,
  value,
  changeLabel,
  changeType,
  icon: Icon,
  color = '#3b82f6',
}: {
  title: string
  value: string | number
  changeLabel: string
  changeType: 'positive' | 'negative' | 'neutral'
  icon: IconType
  color?: string
}) {
  const isPositive = changeType === 'positive'
  const changeClass = isPositive ? 'text-green-500' : changeType === 'negative' ? 'text-red-500' : 'text-muted-foreground'
  const chipGradient = `linear-gradient(135deg, ${color} 0%, ${color}80 100%)`

  return (
    <div className="bg-card rounded-2xl p-6 border border-border shadow-sm relative overflow-hidden">
      <div className="absolute inset-0 pointer-events-none" style={{ background: 'linear-gradient(180deg, rgba(255,255,255,0.03) 0%, rgba(255,255,255,0.0) 100%)' }} />

      <div className="flex items-center justify-between relative">
        <div>
          <p className="text-sm font-medium text-muted-foreground">{title}</p>
          <p className="text-2xl font-bold text-foreground">{value}</p>
        </div>
        <div className="p-3 rounded-xl" style={{ background: chipGradient }}>
          <Icon className="h-6 w-6 text-white" />
        </div>
      </div>

      <div className="mt-4 flex items-center justify-between relative">
        <span className={`text-sm font-medium ${changeClass}`}>{changeLabel}</span>
        <span className="text-sm text-muted-foreground ml-2">mês anterior</span>
        <svg width="140" height="36" viewBox="0 0 140 36" className="overflow-visible">
          <path d="M 0,24 C 20,28 40,20 60,26 C 80,30 100,22 120,26 C 130,28 140,24 140,24" fill="none" stroke="rgba(255,255,255,0.25)" strokeWidth={2} />
        </svg>
      </div>
    </div>
  )
}

