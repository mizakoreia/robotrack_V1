// ClientDashboardPage component
// Dashboard para usuários do tipo cliente, sem valores financeiros
import PageHeader from '@/components/PageHeader'
import { useAuthStore } from '@/store/authStore'

export function ClientDashboardPage() {
  const user = useAuthStore((s) => s.user)
  

  return (
    <div className="space-y-6 overflow-hidden">
      <PageHeader title="Dashboard" subtitle={`Bem-vindo${user?.name ? `, ${user.name}` : ''}`} />

      <div className="bg-card rounded-lg p-6 border border-border">
        <h2 className="text-lg font-semibold text-foreground mb-2">Dashboard do Cliente</h2>
        <p className="text-sm text-muted-foreground">Em breve esta área será implementada com indicadores e gráficos relevantes para clientes.</p>
      </div>
    </div>
  )
}
