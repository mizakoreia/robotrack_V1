import { useRef } from 'react'
import { IconButton } from '@/components/ui/IconButton'

// hierarchy-screens 6.1 (§3.7, D-F) — 4 gatilhos, 1 submit: <form role=search> +
// <input type=search enterKeyHint=search inputMode=search> (Enter e a tecla "buscar"
// do teclado mobile disparam submit nativamente) + botão submit + botão limpar.
export function HierarchySearchField({
  value,
  onChange,
  onSubmit,
  onClear,
}: {
  value: string
  onChange: (v: string) => void
  onSubmit: () => void
  onClear: () => void
}) {
  const inputRef = useRef<HTMLInputElement>(null)
  return (
    <form
      role="search"
      onSubmit={(e) => {
        e.preventDefault()
        onSubmit()
        inputRef.current?.focus() // 7.2 — o foco fica no campo (o leitor não pula p/ a lista)
      }}
      className="surface-panel flex items-center gap-2 rounded-lg border px-3 py-2"
    >
      <input
        ref={inputRef}
        type="search"
        enterKeyHint="search"
        inputMode="search"
        value={value}
        onChange={(e) => onChange(e.target.value)}
        placeholder="Buscar projeto, célula ou robô"
        aria-label="Buscar projeto, célula ou robô"
        // fonte ≥ 16px evita o zoom-no-foco do iOS (7.1)
        className="h-8 min-w-0 flex-1 bg-transparent text-base text-text-main outline-none placeholder:text-text-muted"
      />
      {value && <IconButton icon="close" label="Limpar busca" size="sm" onClick={onClear} />}
      <button type="submit" className="label-md rounded-md bg-accent px-3 py-1 font-medium text-accent-ink">
        Buscar
      </button>
    </form>
  )
}
