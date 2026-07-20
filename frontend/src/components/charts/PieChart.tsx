// Componente de gráfico de pizza (simplificado)
// Renderiza uma legenda textual com percentuais; visual pie pode ser adicionado depois.


export function PieChart({ items }: { items: { label: string; value: number; percent: number }[] }) {
  return (
    <div className="flex gap-3" aria-label="Gráfico de pizza" role="list">
      {items.map((d) => (
        <div role="listitem" key={d.label} className="text-sm text-muted-foreground">
          {d.label}: {Math.round(d.percent * 100)}%
        </div>
      ))}
    </div>
  )
}

