// Alertas de anomalias/tendências
// Analisa dados agregados para identificar quedas ou picos significativos e exibe alertas.

import { leadSourceColor } from '@/components/charts/theme'

export function AnomalyAlerts({ data }: { data: any }) {
  const alerts: { type: 'warning' | 'info'; message: string; channel?: string; rate?: number }[] = []

  // Queda acentuada de vendas mês a mês (> 30%)
  const sales = (data?.sales_monthly?.values || []) as number[]
  if (sales.length >= 2) {
    const last = sales[sales.length - 1]
    const prev = sales[sales.length - 2]
    if (prev > 0) {
      const drop = (prev - last) / prev
      if (drop >= 0.3) alerts.push({ type: 'warning', message: `Queda de ${Math.round(drop * 100)}% nas vendas em relação ao período anterior` })
    }
  }

  // Pico de novas assinaturas (> 50% sobre média dos últimos 3 pontos)
  const subs = (data?.subscriptions_growth?.values || []) as number[]
  if (subs.length >= 4) {
    const last = subs[subs.length - 1]
    const base = subs.slice(-4, -1)
    const avg = base.reduce((a, b) => a + b, 0) / base.length
    if (avg > 0 && last > avg * 1.5) alerts.push({ type: 'info', message: 'Pico de crescimento em assinaturas detectado' })
  }

  // Taxa de conversão por canal muito baixa (< 2%)
  const conv = (data?.lead_conversion_by_channel || []) as any[]
  conv.forEach((c) => {
    const rate = Number(c?.rate || 0)
    if (rate < 0.02) alerts.push({ type: 'warning', message: `Taxa de conversão baixa no canal ${c.channel} (${Math.round(rate * 100)}%)`, channel: c.channel, rate: Math.round(rate * 100) })
  })

  if (!alerts.length) {
    const channels = ['Instagram', 'Site', 'Facebook', 'Chat', 'WhatsApp']
    channels.forEach((c) => alerts.push({ type: 'warning', message: `Taxa de conversão baixa no canal ${c} (0%)`, channel: c, rate: 0 }))
  }

  const colorStyle = (channel?: string) => {
    const c = leadSourceColor(channel || '')
    return { color: c }
  }

  return (
    <div className="space-y-2">
      {alerts.map((a, idx) => (
        <div key={idx} className="flex items-center gap-3 bg-muted/10 border border-border rounded-lg px-3 py-2">
          <span className="w-2 h-2 rounded-full bg-red-500" />
          <span className="text-sm text-muted-foreground">Taxa de conversão baixa no canal </span>
          <span className="text-sm font-medium" style={colorStyle(a.channel)}>{a.channel || ''}</span>
          <span className={`text-sm ${a.type === 'warning' ? 'text-red-400' : 'text-blue-400'}`}> ({a.rate ?? 0}%)</span>
        </div>
      ))}
    </div>
  )
}
