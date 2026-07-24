import { useRef, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { toast } from 'sonner'
import { authApi } from '../../lib/api/endpoints'
import { useAuthStore } from '../../store/authStore'
import { withStorageTimeout } from '../../lib/safeStorage'
import { handleInviteAfterAuth } from '../../lib/auth/session'
import { oauthState } from '../../lib/auth/oauthState'

type Mode = 'login' | 'signup'
type FieldErrors = { name?: string; email?: string; password?: string; form?: string }

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/
const MIN_PASSWORD = 6

// Tela única de login e cadastro (identity-and-auth 5.1/5.2 / §3.1). Um só
// formulário alterna entre os modos; o campo Nome só aparece (e só é exigido) no
// cadastro; o e-mail digitado sobrevive à alternância. A validação do cliente
// espelha o servidor (senha ≥ 6, e-mail com formato) e os erros 422/409/401 são
// mapeados ao campo certo, sem virar "erro inesperado" genérico.
export function AuthPage() {
  const navigate = useNavigate()
  const [mode, setMode] = useState<Mode>('login')
  const [name, setName] = useState('')
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [remember, setRemember] = useState(false)
  const [errors, setErrors] = useState<FieldErrors>({})
  const [loading, setLoading] = useState(false)
  const nameRef = useRef<HTMLInputElement>(null)

  const isSignup = mode === 'signup'

  function switchMode(next: Mode) {
    if (next === mode) return
    setMode(next)
    setErrors({})
    // E-mail sobrevive à alternância (§3.1). Ao entrar no cadastro, o Nome recebe
    // o foco.
    if (next === 'signup') {
      setTimeout(() => nameRef.current?.focus(), 0)
    }
  }

  function validate(): FieldErrors {
    const e: FieldErrors = {}
    if (isSignup && name.trim().length < 2) e.name = 'Informe seu nome (mínimo 2 caracteres).'
    if (!EMAIL_RE.test(email)) e.email = 'Informe um e-mail válido.'
    if (password.length < MIN_PASSWORD) e.password = `A senha precisa ter ao menos ${MIN_PASSWORD} caracteres.`
    return e
  }

  function mapServerError(err: unknown) {
    const status = (err as { response?: { status?: number } })?.response?.status
    const body = (err as { response?: { data?: any } })?.response?.data

    if (status === 401) {
      // Credenciais inválidas: limpa APENAS a senha, mantém o e-mail.
      setPassword('')
      setErrors({ password: 'E-mail ou senha inválidos.' })
      return
    }
    if (status === 409) {
      // E-mail já cadastrado: mensagem no campo de e-mail, senha preservada.
      setErrors({ email: 'Este e-mail já está cadastrado.' })
      return
    }
    if (status === 422 && body?.errors) {
      const fe: FieldErrors = {}
      if (body.errors.name) fe.name = String([].concat(body.errors.name)[0])
      if (body.errors.email) fe.email = String([].concat(body.errors.email)[0])
      if (body.errors.password) fe.password = String([].concat(body.errors.password)[0])
      setErrors(Object.keys(fe).length ? fe : { form: 'Não foi possível concluir. Verifique os dados.' })
      return
    }
    setErrors({ form: 'Algo deu errado. Tente novamente.' })
  }

  async function onSubmit(ev: React.FormEvent) {
    ev.preventDefault()
    const clientErrors = validate()
    if (Object.keys(clientErrors).length) {
      setErrors(clientErrors)
      return // NENHUMA requisição de rede quando a validação do cliente falha.
    }

    setLoading(true)
    try {
      const res = isSignup
        ? await authApi.register({ name: name.trim(), email, password, remember_me: remember })
        : await authApi.login({ email, password, remember_me: remember })

      const { access_token, user } = res.data

      // Handshake do storage contra 1500ms (§3.1): o login não trava mesmo se o
      // storage pendurar; se não persistir, avisa e segue em memória.
      const { timedOut } = await withStorageTimeout(() => {
        useAuthStore.getState().setSession(access_token, user, { remember })
        return useAuthStore.getState().memoryOnly
      })
      if (timedOut || useAuthStore.getState().memoryOnly) {
        toast.warning('Sua sessão não vai persistir neste navegador.')
      }

      await handleInviteAfterAuth()
      navigate('/dashboard')
    } catch (err) {
      mapServerError(err)
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-background px-4">
      <form onSubmit={onSubmit} noValidate className="w-full max-w-sm space-y-4" aria-label={isSignup ? 'Cadastro' : 'Login'}>
        <h1 className="text-2xl font-semibold text-center">
          {isSignup ? 'Criar conta' : 'Entrar'}
        </h1>

        {isSignup && (
          <div>
            <label htmlFor="name" className="block text-sm font-medium">Nome</label>
            <input
              id="name"
              ref={nameRef}
              type="text"
              required
              aria-required="true"
              aria-invalid={!!errors.name}
              value={name}
              onChange={(e) => setName(e.target.value)}
              className="mt-1 w-full rounded border border-input bg-bg-main px-3 py-2 text-text-main placeholder:text-text-muted"
            />
            <p aria-live="polite" className="text-sm text-red-600 min-h-[1.25rem]">{errors.name}</p>
          </div>
        )}

        <div>
          <label htmlFor="email" className="block text-sm font-medium">E-mail</label>
          <input
            id="email"
            type="email"
            autoComplete="email"
            aria-invalid={!!errors.email}
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            className="mt-1 w-full rounded border border-input bg-bg-main px-3 py-2 text-text-main placeholder:text-text-muted"
          />
          <p aria-live="polite" className="text-sm text-red-600 min-h-[1.25rem]">{errors.email}</p>
        </div>

        <div>
          <label htmlFor="password" className="block text-sm font-medium">Senha</label>
          <input
            id="password"
            type="password"
            autoComplete={isSignup ? 'new-password' : 'current-password'}
            aria-invalid={!!errors.password}
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            className="mt-1 w-full rounded border border-input bg-bg-main px-3 py-2 text-text-main placeholder:text-text-muted"
          />
          <p aria-live="polite" className="text-sm text-red-600 min-h-[1.25rem]">{errors.password}</p>
        </div>

        <label className="flex items-center gap-2 text-sm">
          <input type="checkbox" checked={remember} onChange={(e) => setRemember(e.target.checked)} />
          Manter conectado
        </label>

        {errors.form && <p role="alert" className="text-sm text-red-600">{errors.form}</p>}

        <button type="submit" disabled={loading} className="w-full rounded bg-primary px-3 py-2 text-white disabled:opacity-60">
          {loading ? 'Enviando…' : isSignup ? 'Criar conta' : 'Entrar'}
        </button>

        <a
          href={authApi.googleRedirectUrl(remember)}
          onClick={() => oauthState.setRemember(remember)}
          className="block w-full rounded border px-3 py-2 text-center"
        >
          Entrar com Google
        </a>

        <p className="text-center text-sm">
          {isSignup ? (
            <button type="button" onClick={() => switchMode('login')} className="underline">
              Já tenho conta — Entrar
            </button>
          ) : (
            <button type="button" onClick={() => switchMode('signup')} className="underline">
              Criar conta
            </button>
          )}
        </p>
      </form>
    </div>
  )
}
