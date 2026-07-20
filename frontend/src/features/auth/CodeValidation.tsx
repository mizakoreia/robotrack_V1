import React, { useState, useRef, useEffect } from 'react'
import { ArrowLeft, Copy, Check } from 'lucide-react'
import { Button } from '@/components/ui/Button'
import { Input } from '@/components/ui/Input'
import { useAuth } from '@/hooks/useAuth'
import { useAuthStore } from '@/store/authStore'
import { toast } from 'sonner'
import { authService } from '@/lib/api/auth'

interface CodeValidationProps {
  email: string
  onBack: () => void
  onSuccess: () => void
}

export const CodeValidation: React.FC<CodeValidationProps> = ({ email, onBack, onSuccess }) => {
  const [code, setCode] = useState(['', '', '', '', '', ''])
  const [loading, setLoading] = useState(false)
  const [copied, setCopied] = useState(false)
  const [invalidShake, setInvalidShake] = useState(false)
  const devToastShown = useRef(false)

  const inputRefs = useRef<(HTMLInputElement | null)[]>([])
  const { validateMagicCode } = useAuth()
  const { loginMethod, devCode, error, clearError } = useAuthStore()

  useEffect(() => {
    if (import.meta.env.MODE === 'development' && devCode && !devToastShown.current) {
      const showDevCodeToast = () => {
        toast.info(
          <div className="space-y-2">
            <p className="text-sm font-medium">Código de verificação (dev):</p>
            <div className="flex items-center gap-2 bg-muted p-2 rounded-md">
              <code className="text-sm font-mono flex-1">{devCode}</code>
              <Button
                variant="ghost"
                size="sm"
                onClick={() => {
                  navigator.clipboard.writeText(devCode)
                  setCopied(true)
                  setTimeout(() => setCopied(false), 2000)
                }}
                className="h-6 px-2"
              >
                {copied ? <Check className="w-3 h-3" /> : <Copy className="w-3 h-3" />}
              </Button>
            </div>
          </div>,
          {
            duration: 8000,
            position: 'top-center',
          }
        )
      }
      devToastShown.current = true
      const timer = setTimeout(showDevCodeToast, 600)
      return () => clearTimeout(timer)
    }
  }, [devCode, copied])



  const handleCodeChange = (index: number, value: string) => {
    if (value.length > 1) return
    setInvalidShake(false)
    
    const newCode = [...code]
    newCode[index] = value
    setCode(newCode)

    if (value && index < 5) {
      inputRefs.current[index + 1]?.focus()
    }

    if (value && index === 5 && newCode.every(digit => digit !== '')) {
      handleSubmit(newCode.join(''))
    }
  }

  const handleKeyDown = (index: number, e: React.KeyboardEvent<HTMLInputElement>) => {
    if (e.key === 'Backspace' && !code[index] && index > 0) {
      inputRefs.current[index - 1]?.focus()
    }
  }

  const handlePaste = (e: React.ClipboardEvent<HTMLInputElement>) => {
    e.preventDefault()
    const pastedData = e.clipboardData.getData('text').slice(0, 6)
    if (/^\d{6}$/.test(pastedData)) {
      const newCode = pastedData.split('')
      setCode(newCode)
      const { setLoginCode } = useAuthStore.getState()
      setLoginCode(pastedData)
      handleSubmit(pastedData)
    }
  }

  const handleSubmit = async (codeValue: string) => {
    if (loading) return
    
    // Validação adicional antes de submeter
    if (!codeValue.trim() || codeValue.length !== 6) {
      toast.error('Por favor, insira o código recebido')
      setInvalidShake(true)
      setTimeout(() => {
        setInvalidShake(false)
        setCode(['', '', '', '', '', ''])
        inputRefs.current[0]?.focus()
      }, 600)
      return
    }
    
    // Verificar se todos os campos são dígitos
    if (!/^\d{6}$/.test(codeValue)) {
      return
    }
    
    setLoading(true)
    try {
      // Set the code in the auth store and validate
      const { setLoginCode } = useAuthStore.getState()
      setLoginCode(codeValue)
      const next = await validateMagicCode()
      if (next === 'complete') {
        setTimeout(() => {
          onSuccess()
        }, 300)
      } else if (next === 'login') {
        // navegação já feita em useAuth
        return
      } else {
        setInvalidShake(true)
        setTimeout(() => {
          setInvalidShake(false)
          setCode(['', '', '', '', '', ''])
          inputRefs.current[0]?.focus()
        }, 600)
        return
      }
    } catch (error: any) {
      console.error('Code validation failed:', error)
      const message = error.response?.data?.error?.message || 'Código inválido ou expirado'
      toast.error(message)
      setInvalidShake(true)
      setTimeout(() => {
        setInvalidShake(false)
        setCode(['', '', '', '', '', ''])
        inputRefs.current[0]?.focus()
      }, 600)
    } finally {
      setLoading(false)
    }
  }

  const [resendCooldown, setResendCooldown] = useState(0)
  useEffect(() => {
    let timer: number | undefined
    if (resendCooldown > 0) {
      timer = window.setInterval(() => {
        setResendCooldown((v) => (v > 0 ? v - 1 : 0))
      }, 1000)
    }
    return () => {
      if (timer) window.clearInterval(timer)
    }
  }, [resendCooldown])

  const handleResend = async () => {
    if (resendCooldown > 0) return
    const { identifier, loginMethod } = useAuthStore.getState()
    try {
      const sanitized = loginMethod === 'email' ? identifier.trim() : identifier.replace(/\D/g, '')
      if (!sanitized) {
        toast.error('Identificador ausente')
        return
      }
      if (loginMethod === 'whatsapp') {
        const len = sanitized.length
        if (len < 11 || len > 15) {
          toast.error('Por favor, insira o WhatsApp com código do país sem + (ex: 5511999999999)')
          return
        }
      }
      await authService.preRegister({ identifier: sanitized, method: loginMethod })
      toast.success('Novo código enviado!')
      setResendCooldown(120)
    } catch (e: any) {
      const msg = e?.response?.data?.error || e?.message || 'Falha ao reenviar código'
      toast.error(msg)
    }
  }



  return (
    <div className="min-h-screen bg-background flex items-center justify-center p-4">
      <div className="w-full max-w-md">
        {/* Card Principal - Estilo Figma */}
        <div className="bg-card rounded-2xl p-8 shadow-2xl border border-border">
          {/* Header */}
          <div className="text-center mb-8">
            <div className="text-xs text-muted-foreground mb-1">{import.meta.env.VITE_APP_NAME || 'robotrack'}</div>
            <h1 className="text-2xl font-medium text-foreground mb-2">
              Verificação
            </h1>
            <p className="text-muted-foreground text-sm">
              {loginMethod === 'email' ? 'Email' : 'WhatsApp'}: {email}
            </p>
          </div>

          {/* Formulário */}
          <form onSubmit={(e) => { e.preventDefault(); handleSubmit(code.join('')); }} className="space-y-6">
            <div>
                <label className="block text-sm text-muted-foreground mb-3">
                  Digite o código de 6 dígitos
                </label>
                <div className={`grid grid-cols-6 gap-3 mb-4 ${invalidShake ? 'animate-shake' : ''}`}>
                  {[0, 1, 2, 3, 4, 5].map((index) => (
                    <Input
                    key={index}
                    ref={(el) => (inputRefs.current[index] = el)}
                    type="text"
                    inputMode="numeric"
                    maxLength={1}
                    value={code[index] || ''}
                    onChange={(e) => handleCodeChange(index, e.target.value.replace(/\D/g, ''))}
                    onKeyDown={(e) => handleKeyDown(index, e)}
                    onPaste={handlePaste}
                      className={`bg-muted border ${invalidShake ? 'border-destructive' : 'border-border'} text-foreground text-center text-lg font-medium focus:outline-none focus:ring-1 ${invalidShake ? 'focus:ring-destructive' : 'focus:ring-ring'} rounded-lg h-12 w-full`}
                      disabled={loading}
                    />
                  ))}
                </div>
                <p className="text-muted-foreground text-xs text-center">
                  O código expira em 5 minutos
                </p>
              </div>

            <Button
              type="submit"
              disabled={loading || code.some(digit => digit === '')}
              variant="uiverse"
              className="px-3.5 py-1.5 text-[0.875rem] h-10 w-full"
            >
              {loading ? (
                <div className="flex items-center justify-center gap-2">
                  <div className="w-4 h-4 border-2 border-gray-300 border-t-black rounded-full animate-spin" />
                  <span>VERIFICANDO...</span>
                </div>
              ) : (
                <span>VERIFICAR CÓDIGO</span>
              )}
            </Button>

            <div className="mt-4">
              <Button
                type="button"
                variant="uiverse"
                className="btn-neutral px-3.5 py-1.5 text-[0.875rem] h-10 w-full"
                onClick={handleResend}
                disabled={resendCooldown > 0}
              >
                {resendCooldown > 0 ? `REENVIAR EM ${Math.floor(resendCooldown / 60)}:${String(resendCooldown % 60).padStart(2, '0')}` : 'REENVIAR CÓDIGO'}
              </Button>
            </div>
          </form>

          <style>{`
            @keyframes shake {
              0%, 100% { transform: translateX(0); }
              20% { transform: translateX(-4px); }
              40% { transform: translateX(4px); }
              60% { transform: translateX(-3px); }
              80% { transform: translateX(3px); }
            }
            .animate-shake { animation: shake 0.6s ease; }
          `}</style>

          {error && (
            <div className="text-destructive text-sm text-center mt-4">
              {error}
            </div>
          )}

          <div className="mt-4">
            <Button
              type="button"
              variant="uiverse"
              className="btn-neutral px-3.5 py-1.5 text-[0.875rem] h-10 w-full"
              onClick={() => { clearError(); setInvalidShake(false); setCode(['','','','','','']); onBack(); }}
            >
              <span className="inline-flex items-center gap-2">
                <ArrowLeft className="w-4 h-4" />
                VOLTAR PARA LOGIN
              </span>
            </Button>
          </div>
        </div>
      </div>
    </div>
  )
}
