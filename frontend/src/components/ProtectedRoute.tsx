// Componente de guarda de rotas protegidas
// Verifica a presença de token e confirma a sessão no servidor antes de liberar o conteúdo.
// Em caso de sessão inválida, remove tokens, limpa store e redireciona para login.
import React, { useEffect, useState } from 'react'
import { Navigate } from 'react-router-dom'
import { useAuthStore } from '@/store/authStore'
import { authService } from '@/lib/api/auth'

interface ProtectedRouteProps {
  children: React.ReactNode
}

export function ProtectedRoute({ children }: ProtectedRouteProps) {
  const { setUser, logout, isAuthenticated } = useAuthStore()
  const [checking, setChecking] = useState(true)
  /* const token = typeof window !== 'undefined' ? localStorage.getItem('access_token') : null */

  // Não sair cedo, sempre verificar sessão no servidor; caso não exista token,
  // a verificação cairá no bloco de erro/invalid e fará logout + redirect.

  useEffect(() => {
    let mounted = true
    // Função que valida a sessão atual no backend e sincroniza o usuário no store
    async function verify() {
      try {
        const res = await authService.checkSessionStatus()
        if ((res?.authenticated || res?.valid) && res.user) {
          setUser?.(res.user as any)
          if (mounted) setChecking(false)
        } else {
          // Sessão inválida: remove tokens e força logout
          localStorage.removeItem('access_token')
          localStorage.removeItem('refresh_token')
          logout()
          if (mounted) setChecking(false)
        }
      } catch {
        // Erro na verificação: assume sessão inválida e faz logout defensivo
        localStorage.removeItem('access_token')
        localStorage.removeItem('refresh_token')
        logout()
        if (mounted) setChecking(false)
      }
    }
    verify()
    return () => {
      mounted = false
    }
  }, [setUser, logout])

  if (!checking && (!localStorage.getItem('access_token') || !isAuthenticated)) {
    return <Navigate to="/login" replace />
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
