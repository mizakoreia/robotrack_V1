import React, { useState } from 'react'
import { Button } from '@/components/ui/Button'
import { Input } from '@/components/ui/Input'
import { PhoneInputGroup } from '@/components/PhoneInputGroup'
import { useAuthStore } from '@/store/authStore'
import { toast } from 'sonner'
/* import { apiClient } from '@/lib/api/client' */

interface Props {
  onBack: () => void
}

export const CompleteRegistration: React.FC<Props> = ({ onBack }) => {
  const { loginMethod, identifier } = useAuthStore()
  const [name, setName] = useState('')
  const [email, setEmail] = useState('')
  const [whatsapp, setWhatsapp] = useState('')
  const [loading, setLoading] = useState(false)

  const isEmailFlow = loginMethod === 'email'

  const validateName = (n: string) => n.trim().length >= 3
  const validateEmail = (e: string) => /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(e)
  const validateWhatsapp = (w: string) => w.replace(/\D/g, '').length >= 10 && w.replace(/\D/g, '').length <= 15

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!validateName(name)) {
      toast.error('Nome deve ter ao menos 3 caracteres')
      return
    }
    if (isEmailFlow) {
      if (!validateWhatsapp(whatsapp)) {
        toast.error('WhatsApp inválido (formato internacional, sem +)')
        return
      }
    } else {
      if (!validateEmail(email)) {
        toast.error('Email inválido')
        return
      }
    }

    setLoading(true)
    try {
      const payload: any = {
        identifier,
        method: loginMethod,
        name,
        code: useAuthStore.getState().loginCode,
      }
      if (isEmailFlow) {
        payload.whatsapp = whatsapp.replace(/\D/g, '')
      } else {
        payload.email = email.trim()
      }

      const resp: any = await (await import('@/lib/api/auth')).authService.completeRegistration(payload)
      const normalized = {
        access_token: resp.access_token ?? resp.token,
        refresh_token: resp.refresh_token,
        user: resp.user
      }
      // Persistir tokens para o ProtectedRoute e interceptors do axios
      if (normalized.access_token) localStorage.setItem('access_token', normalized.access_token)
      if (normalized.refresh_token) localStorage.setItem('refresh_token', normalized.refresh_token)
      useAuthStore.getState().setAuth({ accessToken: normalized.access_token, refreshToken: normalized.refresh_token }, normalized.user)
      toast.success('Cadastro concluído! Bem-vindo.')
      setTimeout(() => { window.location.href = '/dashboard' }, 200)
    } catch (error: any) {
      const msg = error.response?.data?.error?.message || 'Falha ao concluir cadastro'
      toast.error(msg)
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="min-h-screen bg-background flex items-center justify-center p-4">
      <div className="w-full max-w-2xl sm:min-w-[28rem] mx-auto">
        <div className="bg-card rounded-2xl p-8 shadow-2xl border border-border w-full">
          <div className="text-center mb-8">
            <h1 className="text-2xl font-medium text-foreground mb-2">Completar cadastro</h1>
            <p className="text-muted-foreground text-sm">Preencha os dados obrigatórios</p>
          </div>
          <form onSubmit={handleSubmit} className="space-y-4">
            <div>
              <label className="block text-sm text-muted-foreground mb-2">Nome completo</label>
              <Input value={name} onChange={(e) => setName(e.target.value)} placeholder="Seu nome" />
            </div>

            {isEmailFlow ? (
              <div>
                <label className="block text-sm text-muted-foreground mb-2">WhatsApp (com DDI)</label>
                <PhoneInputGroup
                  value={whatsapp}
                  onChange={(normalized) => setWhatsapp(normalized)}
                  className="w-full"
                />
              </div>
            ) : (
              <div>
                <label className="block text-sm text-muted-foreground mb-2">Email</label>
                <Input type="email" value={email} onChange={(e) => setEmail(e.target.value)} placeholder="seu@email.com" />
              </div>
            )}

            <div className="flex items-center gap-2">
              <Button type="submit" disabled={loading} variant="uiverse" className="px-3.5 py-1.5 text-[0.875rem] h-10 w-full">
                <span className="inline-flex items-center gap-1">
                  {loading ? 'SALVANDO...' : 'CONCLUIR CADASTRO'}
                </span>
              </Button>
              <Button type="button" variant="uiverse" className="btn-neutral px-3.5 py-1.5 text-[0.875rem] h-10 w-full" onClick={onBack}>
                <span className="inline-flex items-center gap-1">
                  VOLTAR
                </span>
              </Button>
            </div>
          </form>
        </div>
      </div>
    </div>
  )
}
