// Gráfico de pizza usando Recharts
// Renderiza distribuição de leads por fonte com tooltip.

import { PieChart, Pie, Cell, Tooltip, ResponsiveContainer, Legend } from 'recharts'
import { vibrantPalette } from './theme'

/* const COLORS = ['#0088FE', '#00C49F', '#FFBB28', '#FF8042', '#AA66CC', '#33B5E5'] */

export function RechartsPie({ items }: { items: { label: string; value: number }[] }) {
  const base = (items || []).map((d) => ({ name: d.label, value: Number(d.value || 0) }))
  const total = base.reduce((a, b) => a + b.value, 0)
  const fallbackCats = ['Chat', 'Facebook', 'Instagram', 'Site', 'WhatsApp']
  const data = total > 0 ? base : fallbackCats.map((n) => ({ name: n, value: 1 }))
  const COLORS = vibrantPalette()
  return (
    <div style={{ width: '100%', height: 320 }} aria-label="Gráfico de pizza">
      <ResponsiveContainer width="100%" height="100%">
        <PieChart>
          <Pie data={data} dataKey="value" nameKey="name" innerRadius={80} outerRadius={120} stroke="#0f172a" strokeWidth={4}>
            {data.map((_, index) => (
              <Cell key={`cell-${index}`} fill={COLORS[index % COLORS.length]} />
            ))}
          </Pie>
          <Tooltip content={({ payload }) => {
            if (!payload || !payload.length) return null
            const p: any = payload[0]
            const name = p?.name ?? ''
            const value = Number(p?.value || 0)
            const percent = total > 0 ? ((value / total) * 100).toFixed(1) : '0.0'
            return (
              <div className="rounded-lg px-3 py-2 bg-card border border-border shadow">
                <p className="text-sm text-muted-foreground">{name}</p>
                <p className="text-base font-semibold text-foreground">{value} leads</p>
                <p className="text-xs text-muted-foreground">{percent}%</p>
              </div>
            )
          }} />
          <Legend verticalAlign="bottom" height={24} formatter={(value) => <span style={{ color: 'var(--muted-foreground)' }}>{value}</span>} />
        </PieChart>
      </ResponsiveContainer>
    </div>
  )
}
