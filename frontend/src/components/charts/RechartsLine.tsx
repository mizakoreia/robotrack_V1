// Gráfico de linhas usando Recharts
// Renderiza crescimento de assinaturas com eixos e tooltip.

import { LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer } from 'recharts'
import { getThemeVars } from './theme'

export function RechartsLine({ labels, values }: { labels: string[]; values: number[] }) {
  const data = (labels || []).map((l, i) => ({ label: l, value: Number(values?.[i] || 0) }))
  const theme = getThemeVars()
  const axisStyle = { fill: theme.fgMuted as any }
  return (
    <div style={{ width: '100%', height: 260 }} aria-label="Gráfico de linhas">
      <ResponsiveContainer width="100%" height="100%">
        <LineChart data={data} margin={{ top: 20, right: 20, left: 0, bottom: 20 }}>
          <defs>
            <linearGradient id="lineGradient" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor={theme.accentVibrant} stopOpacity={0.4} />
              <stop offset="100%" stopColor={theme.accentVibrant} stopOpacity={0.05} />
            </linearGradient>
          </defs>
          <CartesianGrid strokeDasharray="3 3" stroke={theme.grid} />
          <XAxis dataKey="label" tick={axisStyle} />
          <YAxis tick={axisStyle} />
          <Tooltip cursor={{ stroke: theme.grid }} content={({ active, payload }) => {
            if (!active || !payload || !payload.length) return null
            const p: any = payload[0]
            const lab = p?.payload?.label ?? ''
            const val = Number(p?.payload?.value || 0)
            return (
              <div className="rounded-lg px-3 py-2 bg-card border border-border shadow">
                <p className="text-sm text-muted-foreground">{lab}</p>
                <p className="text-base font-semibold text-foreground">{val}</p>
              </div>
            )
          }} />
          <Line type="monotone" dataKey="value" stroke={theme.accentVibrant} strokeWidth={3.5} dot={{ r: 3, stroke: theme.accentVibrant }} activeDot={{ r: 6 }} />
        </LineChart>
      </ResponsiveContainer>
    </div>
  )
}
