// App component
import { useEffect } from 'react'
import { Routes, Route } from 'react-router-dom'
import { Toaster } from 'sonner'
import { ThemeProvider } from '@/components/ThemeProvider'
import { initAmbient } from '@/lib/ambient'
import { HomePage } from '@/app/pages/HomePage'
import { AuthPage } from '@/features/auth/AuthPage'
import { OAuthCallbackPage } from '@/features/auth/OAuthCallbackPage'
import { InviteRoute } from '@/features/auth/InviteRoute'
import { ProtectedRoute } from '@/components/ProtectedRoute'
import { AppShell } from '@/app/AppShell'
import { OverviewPage } from '@/app/pages/OverviewPage'
import { ProjectPage } from '@/app/pages/ProjectPage'
import { CellPage } from '@/app/pages/CellPage'
import { RobotRouteKey } from '@/app/pages/RobotRouteKey'
import { MyTasksPage } from '@/app/pages/MyTasksPage'
import { ReportPage } from '@/app/pages/ReportPage'
import { DashboardPage } from '@/app/pages/DashboardPage'
import { UsersPage } from '@/app/pages/UsersPage'
import { ProfilePage } from '@/app/pages/ProfilePage'
import { BuildPage } from '@/app/pages/BuildPage'
import { TeamPanel } from '@/features/team/TeamPanel'
import { IconSprite } from '@/components/icons/sprite'


function App() {
  // design-system 7.1 — inicia a luz ambiente (throttle 32ms, gate por ponteiro
  // fino, congela sob movimento reduzido). Limpa o listener no unmount.
  useEffect(() => initAmbient(), [])

  return (
    <ThemeProvider>
      {/* design-system 3.2 — o sprite de ícones, renderizado UMA vez no topo. */}
      <IconSprite />
      {/* design-system 7.2 — o halo da luz ambiente (nível ambient, sob tudo). */}
      <div className="ambient" aria-hidden="true" />
      <div className="min-h-screen bg-background font-sans antialiased">
        <Routes>
          {/* app-shell-navigation 4.1 — a landing de marketing do template sai de
              `/` (que passa a ser a Visão Geral autenticada) e fica alcançável em
              `/apresentacao` até `seal-template-baseline` decidir seu destino. */}
          <Route path="/apresentacao" element={<HomePage />} />
          <Route path="/entrar" element={<AuthPage />} />
          <Route path="/build" element={<BuildPage />} />

          <Route path="/auth/callback" element={<OAuthCallbackPage />} />
          <Route path="/convite/:token" element={<InviteRoute />} />

          {/* app-shell-navigation 4.1 (§3.10) — a casca PERSISTENTE envolve toda a
              área autenticada: navegar entre destinos não remonta sidebar/topbar. */}
          <Route
            element={
              <ProtectedRoute>
                <AppShell />
              </ProtectedRoute>
            }
          >
            <Route path="/" element={<OverviewPage />} />
            <Route path="/projeto/:id" element={<ProjectPage />} />
            <Route path="/celula/:id" element={<CellPage />} />
            <Route path="/robo/:id" element={<RobotRouteKey />} />
            <Route path="/minhas-tarefas" element={<MyTasksPage />} />
            <Route path="/relatorio" element={<ReportPage />} />
            <Route path="dashboard" element={<DashboardPage />} />
            <Route path="users" element={<UsersPage />} />
            <Route path="profile" element={<ProfilePage />} />
            {/* Painel de equipe (workspace-invitations 4.5). `workspace-settings`
                (§3.9) vai montá-lo dentro da tela de Configurações; até lá ele é
                alcançável por rota própria. */}
            <Route path="configuracoes/equipe" element={<TeamPanel />} />
          </Route>
        </Routes>
        <Toaster />
      </div>
    </ThemeProvider>
  )
}

export default App
/* const APP_NAME = import.meta.env.VITE_APP_NAME || 'robotrack' */
