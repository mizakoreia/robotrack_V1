// Componente de gráfico de barras (SVG)
// Exibe valores por rótulos com barras proporcionais e suporte a acessibilidade.


export function BarChart({ labels, values, height = 160 }: { labels: string[]; values: number[]; height?: number }) {
  const safeValues = Array.isArray(values) && values.length ? values : [0]
  const max = Math.max(...safeValues)
  return (
    <div aria-label="Gráfico de barras" role="img" className="grid grid-cols-12 gap-1" style={{ height }}>
      {safeValues.map((v, idx) => {
        const h = Math.round((v / (max || 1)) * 100)
        const label = labels?.[idx] || `${idx}`
        return <div key={idx} title={`${label}: ${v}`} className="bg-primary" style={{ height: `${h}%` }} />
      })}
    </div>
  )
}
