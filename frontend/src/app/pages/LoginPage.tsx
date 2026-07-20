import { useAuth } from '@/hooks/useAuth'
import { useTheme } from '@/hooks/useTheme'

export function LoginPage() {
  const { theme, setTheme } = useTheme()
  const { loginWithGoogle } = useAuth()
  return (
    <div className="min-h-screen relative bg-background">
      <div className="absolute top-4 right-4">
        <button
          aria-label="Theme-switch"
          role="switch"
          aria-checked={theme === 'dark'}
          onClick={() => setTheme(theme === 'dark' ? 'light' : 'dark')}
          className={`relative h-6 w-12 rounded-full border border-border transition-colors flex items-center shadow-sm overflow-hidden ${theme === 'dark' ? 'bg-black/40' : 'bg-card'}`}
        >
          <span
            className={`absolute top-0.5 left-0.5 h-5 w-5 rounded-full transition-transform duration-200 ${theme === 'dark' ? 'translate-x-6 bg-white' : 'translate-x-0 bg-black'}`}
          />
        </button>
      </div>
      <div className="flex items-center justify-center py-16">
        <div className="w-full max-w-sm space-y-6 px-6">
          <div className="space-y-2 text-center">
            <h1 className="text-2xl font-semibold text-foreground">Entrar no RoboTrack</h1>
            <p className="text-sm text-muted-foreground">Use sua conta Google para continuar.</p>
          </div>
          <button
            onClick={loginWithGoogle}
            className="w-full rounded-md border border-border bg-card px-4 py-2 text-sm font-medium text-foreground transition-colors hover:bg-accent"
          >
            Continuar com Google
          </button>
        </div>
      </div>
    </div>
  )
}