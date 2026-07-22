// App component
import { useEffect } from 'react'
import { Routes, Route } from 'react-router-dom'
import { Toaster } from 'sonner'
import { ThemeProvider } from '@/components/ThemeProvider'
import { initAmbient } from '@/lib/ambient'
import { Layout } from '@/components/Layout'
import { HomePage } from '@/app/pages/HomePage'
import { AuthPage } from '@/features/auth/AuthPage'
import { OAuthCallbackPage } from '@/features/auth/OAuthCallbackPage'
import { InviteRoute } from '@/features/auth/InviteRoute'
import { ProtectedRoute } from '@/components/ProtectedRoute'
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
          <Route path="/" element={<HomePage />} />
          <Route path="/entrar" element={<AuthPage />} />
          <Route path="/build" element={<BuildPage />} />

          <Route path="/auth/callback" element={<OAuthCallbackPage />} />
          <Route path="/convite/:token" element={<InviteRoute />} />
          <Route
            element={
              <ProtectedRoute>
                <Layout />
              </ProtectedRoute>
            }
          >
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
