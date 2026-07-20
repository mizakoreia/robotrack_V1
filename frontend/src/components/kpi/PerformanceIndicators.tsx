// Indicadores de performance vs metas
// Compara KPIs atuais com metas definidas e exibe estado visual


export function PerformanceIndicators({ kpis, targets }: { kpis: { total_sales?: number; new_subscriptions?: number; leads_converted?: number }, targets: { total_sales?: number; new_subscriptions?: number; leads_converted?: number } }) {
  const rows = [
    { label: 'Vendas (R$)', value: kpis.total_sales ?? 0, target: targets.total_sales ?? 0 },
    { label: 'Novas assinaturas (24h)', value: kpis.new_subscriptions ?? 0, target: targets.new_subscriptions ?? 0 },
    { label: 'Leads convertidos (24h)', value: kpis.leads_converted ?? 0, target: targets.leads_converted ?? 0 },
  ]

  return (
    <table className="w-full text-sm">
      <thead>
        <tr>
          <th className="text-left">Indicador</th>
          <th className="text-right">Atual</th>
          <th className="text-right">Meta</th>
          <th className="text-right">Status</th>
        </tr>
      </thead>
      <tbody>
        {rows.map((r) => {
          const ok = r.value >= r.target
          return (
            <tr key={r.label}>
              <td>{r.label}</td>
              <td className="text-right">{typeof r.value === 'number' ? r.value.toLocaleString('pt-BR') : r.value}</td>
              <td className="text-right">{typeof r.target === 'number' ? r.target.toLocaleString('pt-BR') : r.target}</td>
              <td className={`text-right ${ok ? 'text-green-600' : 'text-red-600'}`}>{ok ? '✅ Dentro da meta' : '⚠️ Abaixo da meta'}</td>
            </tr>
          )
        })}
      </tbody>
    </table>
  )
}

