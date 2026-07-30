import { PortalMenu } from '@/components/menu/PortalMenu'
import { useMenu } from '@/components/menu/useMenu'
import { Icon } from '@/components/icons/Icon'
import { Flag } from '@/components/icons/Flag'
import { languageText } from '@/lib/i18n/language'
import { useLanguageStore, type Lang } from '@/store/languageStore'
import { cn } from '@/lib/utils'

// internationalization D-I7 — o seletor de idioma. CONTROLE, não badge (regra dura da
// casa). Dois formatos:
//   - `menu` (padrão): gatilho com BANDEIRA do idioma atual + código (PT/EN) que abre
//     um PortalMenu com DOIS alvos explícitos (Português/English) — nunca um toggle que
//     cicla (ambíguo sob luva; mesmo raciocínio do controle seguir/silenciar).
//   - `segmented`: dois botões lado a lado (bandeira + nome), como o controle de tema
//     no painel Aparência.
// Acessibilidade: `aria-label` bilíngue "Idioma / Language"; a bandeira é `aria-hidden`
// e o NOME acessível é o idioma; alvo de toque ≥40px (luva).
const FLAG: Record<Lang, 'BR' | 'GB'> = { 'pt-BR': 'BR', en: 'GB' }
const ORDER: Lang[] = ['pt-BR', 'en']

interface LanguageSelectProps {
  layout?: 'menu' | 'segmented'
  className?: string
}

export function LanguageSelect({ layout = 'menu', className }: LanguageSelectProps) {
  const lang = useLanguageStore((s) => s.lang)
  const setLang = useLanguageStore((s) => s.setLang)

  if (layout === 'segmented') {
    return (
      <div
        role="group"
        aria-label={languageText.triggerAria}
        className={cn('flex gap-2', className)}
      >
        {ORDER.map((l) => (
          <button
            key={l}
            type="button"
            aria-pressed={lang === l}
            onClick={() => setLang(l)}
            className={cn(
              'inline-flex min-h-[40px] items-center gap-2 rounded-md border px-3 py-1.5 label-md',
              lang === l
                ? 'border-accent bg-accent/15 text-accent-ink'
                : 'border-input bg-bg-main text-text-main hover:bg-accent/10',
            )}
          >
            <Flag country={FLAG[l]} />
            <span>{languageText.option[l]}</span>
          </button>
        ))}
      </div>
    )
  }

  return <MenuVariant lang={lang} setLang={setLang} className={className} />
}

function MenuVariant({
  lang,
  setLang,
  className,
}: {
  lang: Lang
  setLang: (l: Lang) => void
  className?: string
}) {
  const menu = useMenu<HTMLButtonElement>()
  return (
    <>
      <button
        {...menu.triggerProps}
        aria-label={languageText.triggerAria}
        title={languageText.triggerAria}
        className={cn(
          'inline-flex min-h-[40px] min-w-[40px] items-center gap-1.5 rounded-md px-2 py-1.5 text-text-main hover:bg-accent/10',
          className,
        )}
      >
        <Flag country={FLAG[lang]} />
        <span className="label-sm font-medium">{languageText.short[lang]}</span>
        <Icon name="chevron-down" size="sm" className="text-text-muted" />
      </button>
      <PortalMenu
        anchorRef={menu.anchorRef}
        open={menu.open}
        onClose={menu.close}
        label={languageText.menuLabel}
        items={ORDER.map((l) => ({
          label: languageText.option[l],
          onSelect: () => setLang(l),
        }))}
      />
    </>
  )
}
