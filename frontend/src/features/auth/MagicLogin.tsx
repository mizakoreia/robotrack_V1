import React, { useState, useEffect } from 'react'
import { Mail, MessageCircle, Chrome, Facebook } from 'lucide-react'
import { Button } from '@/components/ui/Button'
import { Input } from '@/components/ui/Input'
import { PhoneInputGroup } from '@/components/PhoneInputGroup'
import { useAuth } from '@/hooks/useAuth'
import { cn } from '@/lib/utils'
import { toast } from 'sonner'

interface MagicLoginProps {
  onCodeSent: () => void
}

export const MagicLogin: React.FC<MagicLoginProps> = ({ onCodeSent }) => {
  const {
    loginMethod,
    identifier,
    isLoading,
    error,
    setLoginMethod,
    setIdentifier,
    clearError,
    requestMagicLogin,
    loginWithGoogle,
    loginWithFacebook
  } = useAuth()

  const [localIdentifier, setLocalIdentifier] = useState(identifier)

  useEffect(() => {
    setLocalIdentifier(identifier)
  }, [identifier])

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    
    if (isLoading) return
    
    console.log('Submitting magic login request:', { method: loginMethod, identifier })
    
    // Validação adicional antes de submeter
    if (!identifier.trim()) {
      console.warn('Magic login blocked: empty identifier')
      return // A validação já é feita no hook
    }
    
    if (loginMethod === 'email' && !identifier.includes('@')) {
      console.warn('Magic login blocked: invalid email format')
      return // A validação já é feita no hook
    }
    
    if (loginMethod === 'whatsapp' && identifier.replace(/\D/g, '').length < 11) {
      console.warn('Magic login blocked: invalid whatsapp format (needs country code without +)')
      return // A validação já é feita no hook
    }
    
    const success = await requestMagicLogin()
    if (success) {
      console.log('Magic login request successful, proceeding to code validation')
      const APP_NAME = import.meta.env.VITE_APP_NAME || 'robotrack'
      if (import.meta.env.MODE !== 'development') {
        toast.success(`Código do ${APP_NAME} enviado! Verifique seu email ou WhatsApp.`)
      }
      onCodeSent()
    } else {
      console.log('Magic login request failed')
    }
  }

  const handleMethodChange = (method: 'email' | 'whatsapp') => {
    setLoginMethod(method)
    setLocalIdentifier('')
    clearError()
  }

  const handleInputChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const value = e.target.value
    if (loginMethod === 'whatsapp') {
      const digits = value.replace(/\D/g, '')
      const normalized = digits.startsWith('55') ? digits.slice(0, 13) : digits.slice(0, 15)
      setIdentifier(normalized)
      setLocalIdentifier(formatWhatsApp(normalized))
    } else {
      setLocalIdentifier(value)
      setIdentifier(value)
    }
    if (error) clearError()
  }

  const getPlaceholder = () => {
    return loginMethod === 'email' 
      ? 'seu@email.com' 
      : '+55 (11) 9 0000-0000'
  }

  const formatWhatsApp = (digits: string) => {
    if (!digits) return ''
    if (digits.startsWith('55')) {
      const ddi = digits.slice(0, 2)
      const ddd = digits.slice(2, 4)
      const rest = digits.slice(4)
      if (rest.length <= 4) return `${ddi}${ddd ? ' (' + ddd + ')' : ''} ${rest}`.trim()
      if (rest.length <= 8) return `${ddi} (${ddd}) ${rest.slice(0, 4)}-${rest.slice(4)}`
      // Celular brasileiro: 9 dígitos
      const first = rest.slice(0, 5)
      const last = rest.slice(5, 9)
      return `${ddi} (${ddd}) ${first}-${last}`
    }
    const ddi = digits.slice(0, 3)
    const rem = digits.slice(3)
    if (rem.length <= 2) return `${ddi} ${rem}`.trim()
    if (rem.length <= 6) return `${ddi} (${rem.slice(0, 2)}) ${rem.slice(2)}`
    if (rem.length <= 10) return `${ddi} (${rem.slice(0, 2)}) ${rem.slice(2, rem.length - 4)}-${rem.slice(rem.length - 4)}`
    return `${ddi} (${rem.slice(0, 2)}) ${rem.slice(2, 7)}-${rem.slice(7, 11)}`
  }



  return (
    <div className="min-h-screen bg-background flex items-center justify-center p-4">
      <div className="w-full max-w-md">
        {/* Card Principal - Estilo Figma */}
        <div className="bg-card rounded-2xl p-8 shadow-2xl border border-border">
          {/* Header */}
          <div className="text-center mb-8">
            <h1 className="text-2xl font-medium text-foreground mb-2">
              Bem-vindo
            </h1>
            <p className="text-muted-foreground text-sm">
              Escolha seu método de login preferido
            </p>
          </div>

          {/* Seletor de Método - Segmented Control Figma */}
          <div className="flex mb-6 bg-muted rounded-full p-1">
            <button
              onClick={() => handleMethodChange('email')}
              className={cn(
                "flex-1 flex items-center justify-center gap-2 py-3 px-4 rounded-full text-sm transition-all",
                loginMethod === 'email'
                  ? "bg-accent text-accent-foreground"
                  : "text-muted-foreground hover:text-foreground"
              )}
            >
              <Mail className="w-4 h-4" />
              <span>Email</span>
            </button>
            <button
              onClick={() => handleMethodChange('whatsapp')}
              className={cn(
                "flex-1 flex items-center justify-center gap-2 py-3 px-4 rounded-full text-sm transition-all",
                loginMethod === 'whatsapp'
                  ? "bg-accent text-accent-foreground"
                  : "text-muted-foreground hover:text-foreground"
              )}
            >
              <MessageCircle className="w-4 h-4" />
              <span>WhatsApp</span>
            </button>
          </div>

          {/* Formulário */}
          <form onSubmit={handleSubmit} className="space-y-4">
            <div>
              {loginMethod === 'email' ? (
                <Input
                  type="email"
                  value={localIdentifier}
                  onChange={handleInputChange}
                  placeholder={getPlaceholder()}
                  className="bg-muted border border-border rounded-lg text-foreground placeholder-muted-foreground py-3 px-4 text-sm focus:outline-none focus:ring-1 focus:ring-ring"
                  disabled={isLoading}
                />
              ) : (
                <PhoneInputGroup
                  value={identifier}
                  onChange={(normalized) => {
                    setIdentifier(normalized)
                    setLocalIdentifier(formatWhatsApp(normalized))
                    if (error) clearError()
                  }}
                  disabled={isLoading}
                  className="rounded-lg"
                />
              )}
            </div>

            {error && (
              <div className="text-destructive text-sm">
                {error}
              </div>
            )}

            <Button
              type="submit"
              disabled={isLoading || !localIdentifier.trim()}
              variant="uiverse"
              className="px-3.5 py-1.5 text-[0.875rem] h-10 w-full"
            >
              {isLoading ? (
                <div className="flex items-center justify-center gap-2">
                  <div className="w-4 h-4 border-2 border-muted-foreground/30 border-t-foreground rounded-full animate-spin" />
                  <span>ENVIANDO...</span>
                </div>
              ) : (
                <span className="inline-flex items-center justify-center gap-2">
                  {loginMethod === 'email' ? (
                    <Mail className="w-4 h-4" />
                  ) : (
                    <MessageCircle className="w-4 h-4" />
                  )}
                  {loginMethod === 'email' ? 'ENVIAR CÓDIGO POR EMAIL' : 'ENVIAR CÓDIGO POR WHATSAPP'}
                </span>
              )}
            </Button>
          </form>

          {/* Divisor - Linha simples */}
          <div className="relative my-6">
            <div className="absolute inset-0 flex items-center">
              <div className="w-full border-t border-border" />
            </div>
          </div>

          {/* Texto do divisor */}
          <div className="text-center mb-4">
            <span className="text-xs text-muted-foreground uppercase tracking-wider">
              Ou continue com
            </span>
          </div>

          {/* Botões Sociais */}
          <div className="grid grid-cols-2 gap-3">
            <Button
              onClick={loginWithGoogle}
              variant="uiverse"
              className="btn-neutral px-3.5 py-1.5 text-[0.875rem] h-10 w-full"
            >
              <span className="inline-flex items-center gap-2">
                <Chrome className="w-4 h-4" />
                GOOGLE
              </span>
            </Button>
            <Button
              onClick={loginWithFacebook}
              variant="uiverse"
              className="btn-neutral px-3.5 py-1.5 text-[0.875rem] h-10 w-full"
            >
              <span className="inline-flex items-center gap-2">
                <Facebook className="w-4 h-4" />
                FACEBOOK
              </span>
            </Button>
          </div>

          {/* Rodapé */}
          <div className="mt-8 text-center">
            <p className="text-xs text-muted-foreground leading-relaxed">
              Ao continuar, você concorda com nossos{' '}
              <a href="#" className="text-primary hover:text-primary/80 underline underline-offset-2 transition-colors">
                Termos de Serviço
              </a>{' '}
              e{' '}
              <a href="#" className="text-primary hover:text-primary/80 underline underline-offset-2 transition-colors">
                Política de Privacidade
              </a>
            </p>
          </div>
        </div>       
      </div>
    </div>
  )
}
