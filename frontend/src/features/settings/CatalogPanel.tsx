import { useMemo, useState } from 'react'
import { Icon } from '@/components/icons/Icon'
import { Button } from '@/components/ui/Button'
import {
  useTaskTemplates,
  useRobotApplications,
  useCreateTaskTemplate,
  useDeleteTaskTemplate,
  useUpdateTaskTemplate,
  type TaskTemplateDTO,
} from '@/features/catalog/useTaskTemplates'
import { settingsText as T } from '@/lib/i18n/settings'

// workspace-settings 3.2–3.5 (§3.9, §1.3, D-CATALOG-FILTER) — a tela do catálogo de
// tarefas-base (o CRUD é de task-catalog; aqui a TELA). Tabela agrupada por categoria
// em ordem LEXICOGRÁFICA pelo prefixo; 4 colunas; `view` em modo LEITURA (sem excluir,
// sem adição, sem editor). Regra do filtro (D-CATALOG-FILTER): marcar "Misto / Geral"
// esvazia o filtro (`appFilters: []` = vale p/ todas) e a requisição NUNCA carrega a
// string "Misto / Geral"; marcar uma aplicação específica desmarca "Misto / Geral".

// O valor-sentinela do enum (Robot::APPLICATIONS[0]) que significa "todas". É um
// VALOR de domínio vindo do backend, não cópia de UI — e nunca é ENVIADO (vira []).
const MISTO = 'Misto / Geral'

export function CatalogPanel({ canWrite }: { canWrite: boolean }) {
  const { data: templates, isLoading } = useTaskTemplates()
  const { data: applications } = useRobotApplications()
  const create = useCreateTaskTemplate()
  const del = useDeleteTaskTemplate()
  const update = useUpdateTaskTemplate()

  const apps = applications ?? []
  const grouped = useMemo(() => groupByCategory(templates ?? []), [templates])

  const [cat, setCat] = useState('')
  const [desc, setDesc] = useState('')
  const [filters, setFilters] = useState<string[]>([]) // [] = Misto / Geral
  const [confirmId, setConfirmId] = useState<string | null>(null)
  const [editId, setEditId] = useState<string | null>(null)

  function submit(e: React.FormEvent) {
    e.preventDefault()
    if (!cat.trim() || !desc.trim()) return
    create.mutate(
      { cat: cat.trim(), desc: desc.trim(), weight: 1, appFilters: filters },
      { onSuccess: () => { setCat(''); setDesc(''); setFilters([]) } },
    )
  }

  return (
    <section aria-labelledby="catalog-panel-title" className="space-y-3">
      <div>
        <h2 id="catalog-panel-title" className="panel-header">{T.catalogTitle}</h2>
        <p className="label-sm text-text-muted">{T.catalogSubtitle}</p>
      </div>

      {isLoading ? (
        <p className="text-text-muted">…</p>
      ) : grouped.length === 0 ? (
        <p className="text-text-muted">{T.catalogEmpty}</p>
      ) : (
        <table className="w-full border-collapse text-left text-sm">
          <thead>
            <tr className="label-sm text-text-muted">
              <th className="px-2 py-1">{T.colCategory}</th>
              <th className="px-2 py-1">{T.colDescription}</th>
              <th className="px-2 py-1">{T.colAppFilter}</th>
              {canWrite && <th className="px-2 py-1">{T.colActions}</th>}
            </tr>
          </thead>
          <tbody>
            {grouped.map(([category, rows]) =>
              rows.map((tpl, i) => (
                <tr key={tpl.id} className="border-t align-top">
                  <td className="px-2 py-1 text-text-muted">{i === 0 ? category : ''}</td>
                  <td className="px-2 py-1 text-text-main">{tpl.desc}</td>
                  <td className="px-2 py-1">
                    {canWrite && editId === tpl.id ? (
                      <FilterEditor
                        apps={apps}
                        value={tpl.appFilters}
                        onChange={(next) => { update.mutate({ id: tpl.id, data: { appFilters: next } }); setEditId(null) }}
                      />
                    ) : (
                      <button
                        type="button"
                        disabled={!canWrite}
                        onClick={() => setEditId(tpl.id)}
                        aria-label={canWrite ? T.edit : undefined}
                        className="text-left text-text-muted enabled:hover:text-text-main"
                      >
                        {tpl.appFilters.length === 0 ? T.filterAll : tpl.appFilters.join(', ')}
                      </button>
                    )}
                  </td>
                  {canWrite && (
                    <td className="px-2 py-1">
                      {confirmId === tpl.id ? (
                        <span className="flex items-center gap-2">
                          <button type="button" onClick={() => { del.mutate(tpl.id); setConfirmId(null) }} className="text-danger-ink">
                            {T.deleteYes}
                          </button>
                          <button type="button" onClick={() => setConfirmId(null)} className="text-text-muted">{T.deleteNo}</button>
                        </span>
                      ) : (
                        <button type="button" onClick={() => setConfirmId(tpl.id)} aria-label={`${T.remove} ${tpl.desc}`} className="text-text-muted hover:text-danger-ink">
                          <Icon name="trash" className="h-4 w-4" />
                        </button>
                      )}
                    </td>
                  )}
                </tr>
              )),
            )}
          </tbody>
        </table>
      )}

      {canWrite && (
        <form onSubmit={submit} className="space-y-2 rounded-md border p-3">
          <div className="flex flex-wrap gap-2">
            <input value={cat} onChange={(e) => setCat(e.target.value)} placeholder={T.addCategory} aria-label={T.addCategory} className="input h-9 rounded-md border bg-bg-main px-3 text-sm" />
            <input value={desc} onChange={(e) => setDesc(e.target.value)} placeholder={T.addDescription} aria-label={T.addDescription} className="input h-9 flex-1 rounded-md border bg-bg-main px-3 text-sm" />
          </div>
          <FilterEditor apps={apps} value={filters} onChange={setFilters} />
          <Button type="submit" disabled={create.isPending}>{T.addTemplate}</Button>
        </form>
      )}
    </section>
  )
}

// D-CATALOG-FILTER — o editor multi-seleção. `value` vazio = "Misto / Geral" (todas).
// Marcar "Misto / Geral" → []. Marcar uma aplicação específica → adiciona (e como
// `value` deixa de ser vazio, "Misto / Geral" fica desmarcado). NUNCA envia a string.
export function FilterEditor({ apps, value, onChange }: { apps: string[]; value: string[]; onChange: (next: string[]) => void }) {
  const mistoChecked = value.length === 0
  function toggle(app: string) {
    if (app === MISTO) { onChange([]); return }
    onChange(value.includes(app) ? value.filter((a) => a !== app) : [...value, app])
  }
  return (
    <fieldset className="flex flex-wrap gap-x-4 gap-y-1">
      {apps.map((app) => {
        const checked = app === MISTO ? mistoChecked : value.includes(app)
        return (
          <label key={app} className="flex items-center gap-1.5 text-sm text-text-main">
            <input type="checkbox" checked={checked} onChange={() => toggle(app)} aria-label={app} />
            {app === MISTO ? T.filterAll : app}
          </label>
        )
      })}
    </fieldset>
  )
}

// §1.3 — agrupa por categoria em ordem LEXICOGRÁFICA pela string do prefixo
// (`A.` < `B.` < `C.`); dentro do grupo, mantém a ordem recebida.
function groupByCategory(templates: TaskTemplateDTO[]): [string, TaskTemplateDTO[]][] {
  const map = new Map<string, TaskTemplateDTO[]>()
  for (const t of templates) {
    const list = map.get(t.cat) ?? []
    list.push(t)
    map.set(t.cat, list)
  }
  return [...map.entries()].sort(([a], [b]) => a.localeCompare(b, 'pt-BR'))
}
