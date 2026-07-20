// Componente de gráfico de linhas (SVG)
// Desenha linha a partir de valores, com rótulos implícitos por índice.


export function LineChart({ values, width = 800, height = 160 }: { values: number[]; width?: number; height?: number }) {
  const safeValues = Array.isArray(values) && values.length ? values : [0, 0]
  const max = Math.max(...safeValues)
  const step = safeValues.length ? width / (safeValues.length - 1 || 1) : width
  const points = safeValues.map((v, i) => `${i * step},${height - Math.round((v / (max || 1)) * height)}`).join(' ')
  return (
    <svg width="100%" height={height} aria-label="Gráfico de linhas" role="img">
      <polyline points={points} fill="none" stroke="currentColor" strokeWidth={2} />
    </svg>
  )
}
