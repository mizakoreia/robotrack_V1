import { AuthFlow } from '@/features/auth/AuthFlow'
import { useTheme } from '@/hooks/useTheme'

export function LoginPage() {
  const { theme, setTheme } = useTheme()
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
        <AuthFlow />
      </div>
    </div>
  )
}