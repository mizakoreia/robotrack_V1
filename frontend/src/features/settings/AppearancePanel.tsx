import { useMemo } from 'react'
import { Button } from '@/components/ui/Button'
import { settingsText as T } from '@/lib/i18n/settings'
import { useThemeStore } from '@/store/themeStore'
import { probeStorageLevel } from '@/lib/safeStorage'

// workspace-settings 6.1 (§5.1, §4.2, D-DS-3) — o painel Aparência sobre o
// themeStore existente. Escuro é o PADRÃO e o tema NUNCA deriva do sistema
// operacional (guarda de design-system 4.3). A aplicação da classe é do
// `useTheme` (claro = `.light` na raiz; escuro é o `:root` — a convenção JÁ
// ENTREGUE, não a "classe dark" do texto da tarefa).
//
// Degradação (§4.2 / D7-11): com o armazenamento bloqueado (modo privado), o
// zustand persist não grava — o toggle segue funcionando NA SESSÃO. O nível vem
// da sonda única do safeStorage (não de um probe local): `persistent` grava a
// preferência; qualquer outro nível avisa que o tema vale só nesta sessão.

export function AppearancePanel() {
  const theme = useThemeStore((s) => s.theme)
  const setTheme = useThemeStore((s) => s.setTheme)
  const blocked = useMemo(() => probeStorageLevel() !== 'persistent', [])

  return (
    <section aria-labelledby="appearance-panel-title" className="space-y-3">
      <h2 id="appearance-panel-title" className="panel-header">{T.appearanceTitle}</h2>
      <div className="surface-panel space-y-2 rounded-lg border p-4">
        <p className="label-sm text-text-muted">{T.appearanceSubtitle}</p>
        <div className="flex gap-2" role="group" aria-label={T.appearanceTitle}>
          <Button
            type="button"
            variant={theme === 'dark' ? 'default' : 'ghost'}
            aria-pressed={theme === 'dark'}
            onClick={() => setTheme('dark')}
          >
            {T.themeDark}
          </Button>
          <Button
            type="button"
            variant={theme === 'light' ? 'default' : 'ghost'}
            aria-pressed={theme === 'light'}
            onClick={() => setTheme('light')}
          >
            {T.themeLight}
          </Button>
        </div>
        {blocked && <p className="text-sm text-text-muted" role="status">{T.storageBlocked}</p>}
      </div>
    </section>
  )
}
