
interface SparklineProps {
  data: number[]
  width?: number
  height?: number
  strokeClassName?: string
  fillClassName?: string
}

export function Sparkline({
  data,
  width = 120,
  height = 36,
  strokeClassName = 'stroke-primary',
  fillClassName = 'fill-primary/20',
}: SparklineProps) {
  const series = Array.isArray(data) ? data : []
  const hasData = series.length > 0
  const singlePoint = series.length === 1

  const max = hasData ? Math.max(...series) : 1
  const min = hasData ? Math.min(...series) : 0
  const norm = (v: number) => ((v - min) / (max - min || 1))

  let d = ''
  let area = ''
  let lastY = height

  if (!hasData) {
    const y = height
    d = `M 0,${y} L ${width},${y}`
    area = `M 0,${height} L 0,${y} L ${width},${y} L ${width},${height} Z`
    lastY = y
  } else if (singlePoint) {
    const y = height - norm(series[0]) * height
    d = `M 0,${y} L ${width},${y}`
    area = `M 0,${height} L 0,${y} L ${width},${y} L ${width},${height} Z`
    lastY = y
  } else {
    const points = series.map((v, i) => {
      const x = (i / (series.length - 1)) * width
      const y = height - norm(v) * height
      return `${x},${y}`
    })
    d = `M ${points[0]} L ${points.slice(1).join(' ')}`
    lastY = Number(points[points.length - 1].split(',')[1])
    area = `M 0,${height} L ${points.join(' ')} L ${width},${height} Z`
  }

  return (
    <svg width={width} height={height} viewBox={`0 0 ${width} ${height}`} className="overflow-visible">
      <path d={area} className={fillClassName} />
      <path d={d} className={`${strokeClassName}`} fill="none" strokeWidth={2} />
      <circle cx={width} cy={lastY} r={3} className={`${strokeClassName} fill-background`} />
    </svg>
  )
}
