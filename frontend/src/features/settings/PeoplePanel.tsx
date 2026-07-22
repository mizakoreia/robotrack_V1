import { useState } from 'react'
import { Icon } from '@/components/icons/Icon'
import { Button } from '@/components/ui/Button'
import { usePeople, useAddPerson, useArchivePerson, isMembershipConflict, isNameTaken, type PersonDTO } from './usePeople'
import { settingsText as T } from '@/lib/i18n/settings'

// workspace-settings 2.3 (§3.9, D10/D11) — o painel de Equipe: os responsáveis como
// chips. NENHUM chip é fixo/não-removível (D11 — o sentinela "Não Atribuído" foi
// abolido; "sem responsável" é conjunto vazio, tratado nos SELETORES, não aqui). Só
// `owner`/`edit` veem o "x" e o campo de adição (`canWrite`); `view` vê os chips em
// leitura. Remover é arquivar no servidor; 409 (a pessoa é MEMBRO) vira orientação,
// não erro genérico.
export function PeoplePanel({ canWrite }: { canWrite: boolean }) {
  const { data, isLoading, isError } = usePeople()
  const add = useAddPerson()
  const archive = useArchivePerson()
  const [name, setName] = useState('')
  const [error, setError] = useState<string | null>(null)

  const people = data ?? []

  function submit(e: React.FormEvent) {
    e.preventDefault()
    setError(null)
    if (!name.trim()) {
      setError(T.errorNameBlank)
      return
    }
    add.mutate(name, {
      onSuccess: () => setName(''),
      onError: (err) => setError(isNameTaken(err) ? T.errorNameTaken : T.errorGeneric),
    })
  }

  function remove(person: PersonDTO) {
    setError(null)
    archive.mutate(person.id, {
      onError: (err) => setError(isMembershipConflict(err) ? T.errorHasMembership : T.errorGeneric),
    })
  }

  return (
    <section aria-labelledby="team-panel-title" className="space-y-3">
      <div>
        <h2 id="team-panel-title" className="panel-header">{T.teamTitle}</h2>
        <p className="label-sm text-text-muted">{T.teamSubtitle}</p>
      </div>

      {isLoading ? (
        <p className="text-text-muted">…</p>
      ) : isError ? (
        <p className="text-danger-ink" role="alert">{T.errorGeneric}</p>
      ) : people.length === 0 ? (
        <p className="text-text-muted">{T.teamEmpty}</p>
      ) : (
        <ul className="flex flex-wrap gap-2">
          {people.map((person) => (
            <li key={person.id} className="flex items-center gap-1.5 rounded-pill border bg-bg-sunken px-3 py-1 text-sm">
              <span className="text-text-main">{person.name}</span>
              {person.has_account && <span className="label-sm text-text-muted">· {T.teamMember}</span>}
              {canWrite && (
                <button
                  type="button"
                  onClick={() => remove(person)}
                  aria-label={T.teamRemoveAria(person.name)}
                  className="ml-0.5 rounded-full p-0.5 text-text-muted hover:text-danger-ink"
                >
                  <Icon name="close" className="h-3.5 w-3.5" />
                </button>
              )}
            </li>
          ))}
        </ul>
      )}

      {canWrite && (
        <form onSubmit={submit} className="flex items-center gap-2">
          <input
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder={T.teamAddPlaceholder}
            aria-label={T.teamAddPlaceholder}
            className="input h-9 rounded-md border bg-bg-main px-3 text-sm"
          />
          <Button type="submit" disabled={add.isPending}>{T.teamAdd}</Button>
        </form>
      )}

      {error && <p className="text-sm text-danger-ink" role="alert">{error}</p>}
    </section>
  )
}
