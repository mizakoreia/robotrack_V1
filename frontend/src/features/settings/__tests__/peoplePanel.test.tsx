import { describe, expect, it, vi, beforeEach, afterEach } from 'vitest'
import { render, screen, fireEvent, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import type { ReactNode } from 'react'
import { PeoplePanel } from '@/features/settings/PeoplePanel'
import { peopleApi, type PersonDTO } from '@/lib/api/endpoints'
import { useWorkspaceStore } from '@/store/workspaceStore'

// workspace-settings 2.3/2.4 (§3.9, D10/D11) — o painel de Equipe: chips das
// pessoas, adição, remoção (com 409 "é membro" traduzido), e o gate de escrita
// (`view` não vê "x" nem campo de adição). NENHUM chip fixo (D11).

function person(over: Partial<PersonDTO> = {}): PersonDTO {
  return { id: 'p1', name: 'Ana', has_account: false, ...over }
}

function wrap() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } })
  return ({ children }: { children: ReactNode }) => (
    <QueryClientProvider client={client}>{children}</QueryClientProvider>
  )
}

beforeEach(() => {
  useWorkspaceStore.setState({
    workspaces: [{ id: 'betim', name: 'Betim', role: 'owner' }],
    currentWorkspaceId: 'betim', currentRoleLabel: 'owner',
  })
})
afterEach(() => vi.restoreAllMocks())

describe('PeoplePanel (2.3/2.4)', () => {
  it('lista chips das pessoas; nenhum chip fixo "Não Atribuído"', async () => {
    vi.spyOn(peopleApi, 'list').mockResolvedValue([person({ id: 'a', name: 'Ana' }), person({ id: 'b', name: 'Bruno' })])
    render(<PeoplePanel canWrite />, { wrapper: wrap() })
    expect(await screen.findByText('Ana')).toBeInTheDocument()
    expect(screen.getByText('Bruno')).toBeInTheDocument()
    expect(screen.queryByText('Não Atribuído')).toBeNull()
  })

  it('view: sem "x" de remoção e sem campo de adição', async () => {
    vi.spyOn(peopleApi, 'list').mockResolvedValue([person({ id: 'a', name: 'Ana' })])
    render(<PeoplePanel canWrite={false} />, { wrapper: wrap() })
    await screen.findByText('Ana')
    expect(screen.queryByLabelText('Remover Ana')).toBeNull()
    expect(screen.queryByLabelText('Nome da pessoa')).toBeNull()
  })

  it('adicionar chama a API com nome e limpa o campo', async () => {
    vi.spyOn(peopleApi, 'list').mockResolvedValue([])
    const create = vi.spyOn(peopleApi, 'create').mockResolvedValue(person({ name: 'Fernanda' }))
    render(<PeoplePanel canWrite />, { wrapper: wrap() })
    const input = await screen.findByLabelText('Nome da pessoa')
    fireEvent.change(input, { target: { value: 'Fernanda' } })
    fireEvent.click(screen.getByRole('button', { name: 'Adicionar' }))
    await waitFor(() => expect(create).toHaveBeenCalledWith({ id: expect.any(String), name: 'Fernanda' }))
  })

  it('remover chip de MEMBRO mostra a orientação (409), não erro genérico', async () => {
    vi.spyOn(peopleApi, 'list').mockResolvedValue([person({ id: 'a', name: 'Ana', has_account: true })])
    vi.spyOn(peopleApi, 'archive').mockRejectedValue({ response: { status: 409, data: { error: 'person_has_membership' } } })
    render(<PeoplePanel canWrite />, { wrapper: wrap() })
    await screen.findByText('Ana')
    fireEvent.click(screen.getByLabelText('Remover Ana'))
    expect(await screen.findByText(/é membro do workspace/)).toBeInTheDocument()
  })

  it('nome duplicado (422 name_taken) mostra a mensagem específica', async () => {
    vi.spyOn(peopleApi, 'list').mockResolvedValue([])
    vi.spyOn(peopleApi, 'create').mockRejectedValue({ response: { status: 422, data: { error: 'name_taken' } } })
    render(<PeoplePanel canWrite />, { wrapper: wrap() })
    fireEvent.change(await screen.findByLabelText('Nome da pessoa'), { target: { value: 'Ana' } })
    fireEvent.click(screen.getByRole('button', { name: 'Adicionar' }))
    expect(await screen.findByText('Já existe uma pessoa com esse nome.')).toBeInTheDocument()
  })

  it('estado vazio: "nenhuma pessoa cadastrada", sem chips', async () => {
    vi.spyOn(peopleApi, 'list').mockResolvedValue([])
    render(<PeoplePanel canWrite />, { wrapper: wrap() })
    expect(await screen.findByText('Nenhuma pessoa cadastrada ainda.')).toBeInTheDocument()
    expect(screen.queryByRole('listitem')).toBeNull()
  })
})
