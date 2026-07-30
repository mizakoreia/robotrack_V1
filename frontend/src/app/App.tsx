// App component
import { lazy, Suspense } from 'react'
import { Routes, Route } from 'react-router-dom'
import { Toaster } from 'sonner'
import { ThemeProvider } from '@/components/ThemeProvider'
// quality-and-accessibility 8.4 (D-QA-7) — a landing de marketing arrasta o campfire
// e o `gsap` (pesado); carregá-la EAGER punha `gsap` no chunk de entrada e estourava
// o teto gzip. `lazy` a manda para um chunk próprio, alcançado só em `/apresentacao`.
const HomePage = lazy(() => import('@/app/pages/HomePage').then((m) => ({ default: m.HomePage })))
import { AuthPage } from '@/features/auth/AuthPage'
import { OAuthCallbackPage } from '@/features/auth/OAuthCallbackPage'
import { ProtectedRoute } from '@/components/ProtectedRoute'
import { AppShell } from '@/app/AppShell'
import { OverviewPage } from '@/app/pages/OverviewPage'
import { ProjectPage } from '@/app/pages/ProjectPage'
import { CellPage } from '@/app/pages/CellPage'
import { RobotRouteKey } from '@/app/pages/RobotRouteKey'
import { MyTasksPage } from '@/app/pages/MyTasksPage'
import { ReportPage } from '@/app/pages/ReportPage'
import { AjudaPage } from '@/app/pages/AjudaPage'
import { DashboardPage } from '@/app/pages/DashboardPage'
import { UsersPage } from '@/app/pages/UsersPage'
import { ProfilePage } from '@/app/pages/ProfilePage'
import { BuildPage } from '@/app/pages/BuildPage'
import { TeamPanel } from '@/features/team/TeamPanel'
import { SettingsPage } from '@/app/pages/SettingsPage'
import { IconSprite } from '@/components/icons/sprite'


function App() {
  return (
    <ThemeProvider>
      {/* design-system 3.2 — o sprite de ícones, renderizado UMA vez no topo. */}
      <IconSprite />
      <div className="min-h-screen bg-background font-sans antialiased">
        <Routes>
          {/* app-shell-navigation 4.1 — a landing de marketing do template sai de
              `/` (que passa a ser a Visão Geral autenticada) e fica alcançável em
              `/apresentacao` até `seal-template-baseline` decidir seu destino. */}
          <Route path="/apresentacao" element={<Suspense fallback={null}><HomePage /></Suspense>} />
          <Route path="/entrar" element={<AuthPage />} />
          <Route path="/build" element={<BuildPage />} />

          <Route path="/auth/callback" element={<OAuthCallbackPage />} />

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
            {/* ajuda-screen — tela de Ajuda; alcançável pelo "?" da topbar. */}
            <Route path="/ajuda" element={<AjudaPage />} />
            <Route path="dashboard" element={<DashboardPage />} />
            <Route path="users" element={<UsersPage />} />
            <Route path="profile" element={<ProfilePage />} />
            {/* Painel de equipe (workspace-invitations 4.5). `workspace-settings`
                (§3.9) vai montá-lo dentro da tela de Configurações; até lá ele é
                alcançável por rota própria. */}
            <Route path="configuracoes/equipe" element={<TeamPanel />} />
            {/* workspace-settings 6.x — a tela de Configurações (§3.9/§3.11). */}
            <Route path="configuracoes" element={<SettingsPage />} />
          </Route>
        </Routes>
        <Toaster />
      </div>
    </ThemeProvider>
  )
}

export default App
/* const APP_NAME = import.meta.env.VITE_APP_NAME || 'robotrack' */
