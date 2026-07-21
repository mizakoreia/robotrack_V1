// Guarda de rotas para páginas administrativas (OG/Super)
// Exige autenticação e role adequada antes de permitir acesso.
import React from 'react'
import { Navigate } from 'react-router-dom'
import { useAuthStore } from '@/store/authStore'

export function OgRoute({ children }: { children: React.ReactNode }) {
  const { user, isAuthenticated, accessToken } = useAuthStore()

  if (!accessToken) return <Navigate to="/entrar" replace />

  const t = ((user as { user_type?: string } | null)?.user_type || '').toLowerCase()
  const allowed = isAuthenticated && (t.includes('og') || t.includes('super'))
  if (!allowed) return <Navigate to="/dashboard" replace />

  return <>{children}</>
}
