import { describe, expect, it, vi, beforeEach } from 'vitest'
import { renderHook, act, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import type { ReactNode } from 'react'
import {
  useReplaceAssignees,
  useAssigneeSelection,
  useWorkspacePeople,
  peopleKey,
} from '../useTaskAssignees'
import { catalogKeys } from '../../../lib/api/catalogKeys'

// robot-tasks 4.5 (§3.5, §2.7, D9, D-RT-6) — a lógica do modal de atribuição:
// substituir o conjunto invalida as TAREFAS do robô; a seleção parte dos
// responsáveis atuais; a pessoa cadastrada no modal já sai marcada e sobrevive.
// O backend de `POST /people` é de workspace-tenancy (mockado aqui).

const WS = 'ws-teste'

vi.mock('../../../store/workspaceStore', () => ({
  useWorkspaceStore: (selector: (s: { currentWorkspaceId: string }) => unknown) =>
    selector({ currentWorkspaceId: WS }),
}))

const api = { replace: vi.fn(), createPerson: vi.fn(), listMembers: vi.fn() }

vi.mock('../../../lib/api/endpoints', async (original) => {
  const real = await original<typeof import('../../../lib/api/endpoints')>()
  return {
    ...real,
    taskAssigneesApi: { replace: (...a: unknown[]) => api.replace(...a) },
    peopleApi: { create: (...a: unknown[]) => api.createPerson(...a) },
    membershipsApi: { ...real.membershipsApi, list: (...a: unknown[]) => api.listMembers(...a) },
  }
})

function wrapper(client: QueryClient) {
  return ({ children }: { children: ReactNode }) => (
    <QueryClientProvider client={client}>{children}</QueryClientProvider>
  )
}

function newClient() {
  return new QueryClient({ defaultOptions: { queries: { retry: false } } })
}

beforeEach(() => {
  Object.values(api).forEach((f) => f.mockReset())
})

describe('useReplaceAssignees', () => {
  it('envia o conjunto de person_ids e invalida as tarefas do robô', async () => {
    const client = newClient()
    const spy = vi.spyOn(client, 'invalidateQueries')
    api.replace.mockResolvedValue({ added: ['p3'], removed: ['p1'] })

    const { result } = renderHook(() => useReplaceAssignees('robo-1'), { wrapper: wrapper(client) })
    act(() => {
      result.current.mutate({ taskId: 't1', personIds: ['p2', 'p3'] })
    })

    await waitFor(() => expect(result.current.isSuccess).toBe(true))
    expect(api.replace).toHaveBeenCalledWith('t1', ['p2', 'p3'])
    expect(spy).toHaveBeenCalledWith({ queryKey: catalogKeys.robotTasks(WS, 'robo-1') })
  })
})

describe('useAssigneeSelection', () => {
  it('parte dos responsáveis atuais e alterna com toggle', () => {
    const client = newClient()
    const { result } = renderHook(() => useAssigneeSelection(['p1', 'p2']), { wrapper: wrapper(client) })

    expect(result.current.personIds().sort()).toEqual(['p1', 'p2'])
    act(() => result.current.toggle('p1')) // remove
    expect(result.current.personIds()).toEqual(['p2'])
    act(() => result.current.toggle('p3')) // adiciona
    expect(result.current.personIds().sort()).toEqual(['p2', 'p3'])
  })

  it('cadastra pessoa nova: já sai marcada e entra no cache de people (sobrevive)', async () => {
    const client = newClient()
    client.setQueryData(peopleKey(WS), [{ id: 'p1', name: 'Ana' }])
    api.createPerson.mockResolvedValue({ id: 'p-novo', name: 'Nova Pessoa' })

    const { result } = renderHook(() => useAssigneeSelection([]), { wrapper: wrapper(client) })

    await act(async () => {
      await result.current.createAndSelect('Nova Pessoa')
    })

    expect(result.current.personIds()).toContain('p-novo') // já marcada
    const cache = client.getQueryData<{ id: string; name: string }[]>(peopleKey(WS))
    expect(cache?.map((p) => p.id)).toEqual(['p1', 'p-novo']) // sobrevive no cache
    expect(api.createPerson).toHaveBeenCalledWith(expect.objectContaining({ name: 'Nova Pessoa' }))
  })
})

describe('useWorkspacePeople', () => {
  it('deriva as pessoas dos membros (person_id + name)', async () => {
    const client = newClient()
    api.listMembers.mockResolvedValue([
      { id: 'm1', person_id: 'p1', name: 'Ana', email: 'a@x', role: 'owner', is_owner: true, invitation_id: null },
      { id: 'm2', person_id: null, name: null, email: null, role: 'edit', is_owner: false, invitation_id: 'i1' },
    ])

    const { result } = renderHook(() => useWorkspacePeople(), { wrapper: wrapper(client) })

    await waitFor(() => expect(result.current.isSuccess).toBe(true))
    expect(result.current.data).toEqual([{ id: 'p1', name: 'Ana' }]) // membro sem person_id é ignorado
  })
})
