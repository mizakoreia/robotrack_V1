import { useNavigate } from 'react-router-dom'
import { Icon } from '@/components/icons/Icon'
import { Button } from '@/components/ui/Button'
import type { IconName } from '@/components/icons/sprite'
import { useHierarchySearch, type SearchResult } from './useSearch'

const TYPE_ICON: Record<SearchResult['type'], IconName> = {
  project: 'file',
  cell: 'list',
  robot: 'home',
}

// hierarchy-screens 6.4 (§3.7) — a lista plana de resultados: ícone do tipo, nome,
// path_label (do servidor) e navegação ao destino; contador com aria-live; vazio que
// NOMEIA o termo, com botão limpar.
export function SearchResults({ query, onClear }: { query: string; onClear: () => void }) {
  const navigate = useNavigate()
  const { data, isFetching } = useHierarchySearch(query)

  if (!data && isFetching) return <p className="text-text-muted">Buscando…</p>

  const results = data?.results ?? []

  if (results.length === 0) {
    return (
      <div className="surface-panel flex flex-col items-center rounded-lg border p-10 text-center">
        <p className="mb-4 text-text-muted">
          Nenhum resultado para <span className="font-medium text-text-main">"{query}"</span>
        </p>
        <Button variant="outline" onClick={onClear}>
          Limpar busca
        </Button>
      </div>
    )
  }

  return (
    <div className="space-y-3">
      <p aria-live="polite" className="label-sm text-text-muted">
        {results.length} {results.length === 1 ? 'resultado' : 'resultados'}
      </p>
      <ul className="surface-panel divide-y divide-border rounded-lg border">
        {results.map((r) => (
          <li key={`${r.type}-${r.id}`}>
            <button
              onClick={() => navigate(r.route)}
              className="flex w-full items-center gap-3 px-4 py-3 text-left hover:bg-accent/10"
            >
              <span className="grid h-8 w-8 shrink-0 place-content-center rounded-md bg-accent/15 text-accent-ink">
                <Icon name={TYPE_ICON[r.type]} size="sm" />
              </span>
              <span className="min-w-0 flex-1">
                <span className="label-md block truncate font-medium text-text-main">{r.name}</span>
                <span className="label-sm block truncate text-text-muted">{r.path_label}</span>
              </span>
            </button>
          </li>
        ))}
      </ul>
    </div>
  )
}
