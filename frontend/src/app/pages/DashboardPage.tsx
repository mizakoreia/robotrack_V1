// DashboardPage component
import PageHeader from '@/components/PageHeader'
import { useAuthStore } from '@/store/authStore'
import { SetupPage } from './SetupPage'

export function DashboardPage() {
  const user = useAuthStore((s) => s.user)

  if (user?.user_type === 'client' || user?.is_og === false) {
    return <SetupPage />
  }

  return (
    <div className="space-y-6 overflow-hidden">
      <PageHeader title="Dashboard" subtitle="Bem-vindo ao painel administrativo" />
      <div className="bg-card rounded-lg p-6 border border-border">
        <h2 className="text-lg font-semibold text-foreground mb-4">Olá, {user?.name}</h2>
        <p className="text-muted-foreground">Seja bem-vindo ao sistema.</p>
      </div>
    </div>
  )
}

