// Guarda de rotas protegidas (identity-and-auth 6.x). O token tem uma fonte
// única — o authStore. Sem token, redireciona para /entrar. Com token, confirma
// a identidade em GET /auth/v1/me e sincroniza o usuário; um 401 já encerra a
// sessão pelo interceptor do cliente.
import React, { useEffect, useState } from 'react'
import { Navigate } from 'react-router-dom'
import { useAuthStore } from '@/store/authStore'
import { authApi } from '@/lib/api/endpoints'

interface ProtectedRouteProps {
  children: React.ReactNode
}

export function ProtectedRoute({ children }: ProtectedRouteProps) {
  const accessToken = useAuthStore((s) => s.accessToken)
  const isAuthenticated = useAuthStore((s) => s.isAuthenticated)
  const [checking, setChecking] = useState(!!accessToken)

  useEffect(() => {
    if (!accessToken) {
      setChecking(false)
      return
    }
    let mounted = true
    authApi
      .me()
      .then(({ data }) => {
        if (mounted) {
          useAuthStore.getState().setUser(data.user)
          setChecking(false)
        }
      })
      .catch(() => {
        // 401 é tratado pelo interceptor (encerra a sessão). Outros erros: solta.
        if (mounted) setChecking(false)
      })
    return () => {
      mounted = false
    }
  }, [accessToken])

  if (!accessToken || !isAuthenticated) {
    return <Navigate to="/entrar" replace />
  }

  if (checking) {
    return (
      <div className="flex h-screen items-center justify-center">
        <span className="text-sm text-muted-foreground">Verificando sessão…</span>
      </div>
    )
  }

  return <>{children}</>
}
