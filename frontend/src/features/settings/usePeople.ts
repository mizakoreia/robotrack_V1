import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { peopleApi } from '../../lib/api/endpoints'
import { qk } from '../../lib/query/keys'
import { useWorkspaceStore } from '../../store/workspaceStore'
import { newId } from '../../lib/ids'

export type { PersonDTO } from '../../lib/api/endpoints'

// workspace-settings 2.1/2.2 (§3.9, D1/D9) — leitura e mutações do painel de Equipe.
// Chave `qk.people` (`['ws', wsId, 'people']`), partindo por workspace. Criar usa
// `newId()` (uuid do cliente, D1). Ambas as mutações invalidam SÓ `qk.people` (nunca
// o tenant inteiro). O 409 (pessoa é membro) e o 422 (nome) são estados de produto —
// a UI os traduz, não os trata como falha de rede.
export function usePeople() {
  const wsId = useWorkspaceStore((s) => s.currentWorkspaceId)
  return useQuery({
    queryKey: qk.people(wsId ?? '_'),
    queryFn: () => peopleApi.list(),
    enabled: Boolean(wsId),
  })
}

export function useAddPerson() {
  const wsId = useWorkspaceStore((s) => s.currentWorkspaceId)
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (name: string) => peopleApi.create({ id: newId(), name: name.trim() }),
    onSuccess: () => qc.invalidateQueries({ queryKey: qk.people(wsId ?? '_') }),
  })
}

export function useArchivePerson() {
  const wsId = useWorkspaceStore((s) => s.currentWorkspaceId)
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (id: string) => peopleApi.archive(id),
    onSuccess: () => qc.invalidateQueries({ queryKey: qk.people(wsId ?? '_') }),
  })
}

// D-PERSON-DEL — distingue o 409 "é membro" de qualquer outro erro (a UI mostra a
// orientação de remover pela tela de membros, não um erro genérico).
export function isMembershipConflict(error: unknown): boolean {
  const resp = (error as { response?: { status?: number; data?: { error?: string } } })?.response
  return resp?.status === 409 && resp?.data?.error === 'person_has_membership'
}

export function isNameTaken(error: unknown): boolean {
  const resp = (error as { response?: { status?: number; data?: { error?: string } } })?.response
  return resp?.status === 422 && resp?.data?.error === 'name_taken'
}
