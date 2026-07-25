import { useState } from 'react'
import { Button } from '@/components/ui/Button'
import { Chip } from '@/components/ui/Chip'
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
        {/* impeccable-remediation G4 — desambigua as duas telas antes homônimas
            "Equipe": esta é "Responsáveis" (a quem se atribui tarefa); os membros e
            papéis do workspace ficam em /configuracoes/equipe. Link cruzado. */}
        <a href="/configuracoes/equipe" className="label-sm inline-flex min-h-[2rem] items-center text-accent-ink hover:underline">
          {T.teamManageLink}
        </a>
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
            // impeccable-remediation G4 — primitivo `Chip` (remover = 32×32px) no
            // lugar do chip à mão cujo "x" media ~18px (metade do piso de luva).
            <li key={person.id}>
              <Chip
                label={person.has_account ? `${person.name} · ${T.teamMember}` : person.name}
                onRemove={canWrite ? () => remove(person) : undefined}
              />
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
