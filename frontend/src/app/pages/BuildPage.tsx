import { Button } from '@/components/ui/Button'
import { useTheme } from '@/hooks/useTheme'
import { Link } from 'react-router-dom'
import readme from '../../../../README.md?raw'
import ReactMarkdown from 'react-markdown'
import remarkGfm from 'remark-gfm'

export function BuildPage() {
  const APP_NAME = import.meta.env.VITE_APP_NAME || 'robotrack'
  const { theme, setTheme } = useTheme()

  return (
    <div className={`min-h-screen ${theme === 'dark' ? 'bg-[#0B0F1A]' : 'bg-white'}`}>
      <div className="fixed top-3 left-0 right-0 z-50 pointer-events-none">
        <div className="w-full px-4 md:px-6">
          <div className="pointer-events-auto w-full flex items-center justify-between px-4 md:px-6 py-3">
            <a href="/" className="flex items-center gap-2">
              <div className="flex items-center gap-0 text-xl md:text-2xl font-bold select-none">
                <div className="rounded-[500px] px-[6px] pt-0 pb-[6px] flex items-center gap-0">
                  <span className="text-blue-500">&#123;</span>
                  <span className="text-foreground">{APP_NAME}</span>
                  <span className="text-purple-500">&#125;</span>
                </div>
              </div>
            </a>
            <div className="flex items-center gap-3">
              <button
                aria-label="Alternar tema"
                role="switch"
                aria-checked={theme === 'dark'}
                onClick={() => setTheme(theme === 'dark' ? 'light' : 'dark')}
                className={`relative h-6 w-12 rounded-full border border-border transition-colors flex items-center shadow-sm overflow-hidden ${theme === 'dark' ? 'bg-black/40' : 'bg-card/50'}`}
              >
                <span
                  className={`absolute top-0.5 left-0.5 h-5 w-5 rounded-full transition-transform duration-200 ${theme === 'dark' ? 'translate-x-6 bg-white' : 'translate-x-0 bg-black'}`}
                />
              </button>
              <a href="/login">
                <Button variant="uiverse" className="px-3.5 py-1.5 text-[0.875rem] h-10">
                  <span className="inline-flex items-center justify-center gap-2">Entrar</span>
                </Button>
              </a>
            </div>
          </div>
        </div>
      </div>

      <section className={`relative overflow-hidden ${theme === 'dark' ? 'bg-goat-gradient-dark' : 'bg-goat-gradient-light'}`}>
        <div className="px-6 md:px-12 pt-20 md:pt-28 pb-16 text-center max-w-6xl mx-auto">
          <h1 className="mt-4 text-4xl md:text-5xl font-extrabold tracking-tight text-transparent bg-clip-text bg-gradient-to-r from-fuchsia-500 via-purple-500 to-cyan-400">
            Instruções do Build
          </h1>
          <p className="mt-3 text-sm md:text-base text-muted-foreground max-w-2xl mx-auto">
            Tudo o que você precisa para compilar, testar e publicar — rápido, seguro e bonito.
          </p>
        </div>
      </section>

      <section className="px-6 md:px-12 py-12">
        <div className={`max-w-6xl mx-auto rounded-2xl border border-border ${theme === 'dark' ? 'bg-[#111624]' : 'bg-card'} p-6 md:p-10`}>
          <ReactMarkdown
            remarkPlugins={[remarkGfm]}
            components={{
              h1: ({ children }) => <h1 className="text-3xl md:text-4xl font-bold mb-4">{children}</h1>,
              h2: ({ children }) => <h2 className="text-2xl md:text-3xl font-semibold mt-8 mb-3">{children}</h2>,
              h3: ({ children }) => <h3 className="text-xl md:text-2xl font-semibold mt-6 mb-2">{children}</h3>,
              p: ({ children }) => <p className="text-sm md:text-base text-muted-foreground leading-relaxed mb-3">{children}</p>,
              ul: ({ children }) => <ul className="list-disc pl-6 space-y-1">{children}</ul>,
              ol: ({ children }) => <ol className="list-decimal pl-6 space-y-1">{children}</ol>,
              code: ({ children }) => <code className="px-1 py-0.5 rounded bg-muted text-foreground">{children}</code>,
              pre: ({ children }) => <pre className="overflow-x-auto p-4 rounded bg-muted/50">{children}</pre>,
              a: ({ children, href }) => <a href={href} className="text-primary hover:underline" target="_blank" rel="noopener noreferrer">{children}</a>,
              table: ({ children }) => <div className="overflow-x-auto"><table className="min-w-full">{children}</table></div>,
            }}
          >
            {readme}
          </ReactMarkdown>
        </div>
      </section>

      <footer className="px-6 md:px-12 py-10 border-t border-border">
        <div className="max-w-6xl mx-auto flex flex-col md:flex-row items-center justify-between gap-4">
          <div className="text-sm text-muted-foreground">© {new Date().getFullYear()} {APP_NAME}. Todos os direitos reservados.</div>
          <div className="flex items-center gap-4 text-sm">
            <Link to="/login" className="text-muted-foreground hover:text-foreground">Acessar</Link>
            <Link to="/dashboard" className="text-muted-foreground hover:text-foreground">Dashboard</Link>
          </div>
        </div>
      </footer>
    </div>
  )
}
