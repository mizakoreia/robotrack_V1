// Gráfico de barras usando Recharts
// Renderiza vendas mensais com eixos, tooltip e legenda.

import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer } from 'recharts'
import { getThemeVars } from './theme'

export function RechartsBar({ labels, values }: { labels: string[]; values: number[] }) {
  const data = (labels || []).map((l, i) => ({ label: l, value: Number(values?.[i] || 0) }))
  const theme = getThemeVars()
  const axisStyle = { fill: theme.fgMuted as any }
  return (
    <div style={{ width: '100%', height: 260 }} aria-label="Gráfico de barras">
      <ResponsiveContainer width="100%" height="100%">
        <BarChart data={data} margin={{ top: 20, right: 20, left: 0, bottom: 20 }}>
          <defs>
            <linearGradient id="barGradient" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor={theme.primaryVibrant} stopOpacity={0.95} />
              <stop offset="100%" stopColor={theme.primaryVibrant2} stopOpacity={0.5} />
            </linearGradient>
          </defs>
          <CartesianGrid strokeDasharray="3 3" stroke={theme.grid} />
          <XAxis dataKey="label" tick={axisStyle} />
          <YAxis tick={axisStyle} />
          <Tooltip cursor={{ fill: 'transparent' }} content={({ active, payload }) => {
            if (!active || !payload || !payload.length) return null
            const p: any = payload[0]
            const lab = p?.payload?.label ?? ''
            const val = Number(p?.payload?.value || 0)
            return (
              <div className="rounded-lg px-3 py-2 bg-card border border-border shadow">
                <p className="text-sm text-muted-foreground">{lab}</p>
                <p className="text-base font-semibold text-foreground">R$ {val.toLocaleString('pt-BR', { minimumFractionDigits: 2 })}</p>
              </div>
            )
          }} />
          <Bar dataKey="value" fill="url(#barGradient)" radius={[12, 12, 0, 0]} />
        </BarChart>
      </ResponsiveContainer>
    </div>
  )
}
