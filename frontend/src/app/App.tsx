// App component
import { Routes, Route } from 'react-router-dom'
import { Toaster } from 'sonner'
import { ThemeProvider } from '@/components/ThemeProvider'
import { Layout } from '@/components/Layout'
import { HomePage } from '@/app/pages/HomePage'
import { LoginPage } from '@/app/pages/LoginPage'
import { OAuthCallbackPage } from '@/features/auth/OAuthCallbackPage'
import { ProtectedRoute } from '@/components/ProtectedRoute'
import { DashboardPage } from '@/app/pages/DashboardPage'
import { UsersPage } from '@/app/pages/UsersPage'
import { ProfilePage } from '@/app/pages/ProfilePage'
import { BuildPage } from '@/app/pages/BuildPage'


function App() {
  return (
    <ThemeProvider>
      <div className="min-h-screen bg-background font-sans antialiased">
        <Routes>
          <Route path="/" element={<HomePage />} />
          <Route path="/login" element={<LoginPage />} />
          <Route path="/build" element={<BuildPage />} />

          <Route path="/auth/callback" element={<OAuthCallbackPage />} />
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
          </Route>
        </Routes>
        <Toaster />
      </div>
    </ThemeProvider>
  )
}

export default App
/* const APP_NAME = import.meta.env.VITE_APP_NAME || 'robotrack' */
