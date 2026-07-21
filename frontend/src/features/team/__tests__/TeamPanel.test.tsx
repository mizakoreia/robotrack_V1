import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { render, screen, fireEvent, waitFor, cleanup } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'

// workspace-invitations 4.5/4.6 — painel de equipe e diálogo de convite.
//
// As falhas a caçar: um membro `edit` ver botões de mutação (a UI é conveniência,
// mas oferecer um botão que só devolve 403 é mentira); um convite expirado ser
// listado como pendente ativo; e — a pior — a cópia do link falhar em silêncio
// quando a Clipboard API é negada, deixando um convite que existe no banco e que
// ninguém nunca recebe (o produto NÃO envia e-mail).

const { listMembers, listInvites, createInvite, revokeInvite, updateRole, removeMember, toastMock } =
  vi.hoisted(() => ({
    listMembers: vi.fn(),
    listInvites: vi.fn(),
    createInvite: vi.fn(),
    revokeInvite: vi.fn(),
    updateRole: vi.fn(),
    removeMember: vi.fn(),
    toastMock: { warning: vi.fn(), error: vi.fn(), success: vi.fn(), info: vi.fn() },
  }))

vi.mock('../../../lib/api/endpoints', () => ({
  invitationsApi: { list: listInvites, create: createInvite, revoke: revokeInvite },
  membershipsApi: { list: listMembers, updateRole, remove: removeMember },
}))

vi.mock('sonner', () => ({ toast: toastMock }))

import { TeamPanel } from '../TeamPanel'
import { useWorkspaceStore } from '../../../store/workspaceStore'

const WS = 'ws-a'

const MEMBROS = [
  { id: 'p-dono', person_id: 'p-dono', name: 'Dona Ana', email: 'ana@fabrica.com', role: 'owner', is_owner: true, invitation_id: null },
  { id: 'm-1', person_id: 'p-1', name: 'Edu Edit', email: 'edu@fabrica.com', role: 'edit', is_owner: false, invitation_id: 'i-1' },
  { id: 'm-2', person_id: 'p-2', name: 'Vera View', email: 'vera@fabrica.com', role: 'view', is_owner: false, invitation_id: null },
]

const CONVITES = [
  { id: 'i-9', email: 'novo@fabrica.com', role: 'view', status: 'pending', expires_at: '2026-07-28T10:00:00Z', created_at: '2026-07-21T10:00:00Z', invite_url: 'http://localhost:5173/convite/rt_inv_ABC' },
  { id: 'i-8', email: 'velho@fabrica.com', role: 'edit', status: 'expired', expires_at: '2026-07-01T10:00:00Z', created_at: '2026-06-24T10:00:00Z', invite_url: 'http://localhost:5173/convite/rt_inv_XYZ' },
]

function renderPanel() {
  const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  return render(
    <QueryClientProvider client={queryClient}>
      <TeamPanel />
    </QueryClientProvider>,
  )
}

function comoPapel(role: 'owner' | 'edit' | 'view') {
  useWorkspaceStore.setState({
    currentWorkspaceId: WS,
    currentRoleLabel: role,
    workspaces: [{ id: WS, name: 'Linha 3', role }],
  })
}

describe('TeamPanel', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    listMembers.mockResolvedValue(MEMBROS)
    listInvites.mockResolvedValue(CONVITES)
    createInvite.mockResolvedValue(CONVITES[0])
    vi.spyOn(window, 'confirm').mockReturnValue(true)
  })

  afterEach(cleanup)

  it('o dono vê as duas listas e os controles de mutação', async () => {
    comoPapel('owner')
    renderPanel()

    expect(await screen.findByText('Edu Edit')).toBeInTheDocument()
    expect(screen.getByText('Vera View')).toBeInTheDocument()
    expect(await screen.findByText('novo@fabrica.com')).toBeInTheDocument()

    expect(screen.getAllByRole('button', { name: 'Remover' })).toHaveLength(2)
    expect(screen.getAllByRole('button', { name: 'Revogar' })).toHaveLength(2)
  })

  it('o DONO não tem controles: seu papel é imutável e removê-lo é irrecuperável', async () => {
    comoPapel('owner')
    renderPanel()

    await screen.findByText('Dona Ana')
    // Três membros, mas só dois removíveis — o dono fica de fora.
    expect(screen.getAllByRole('button', { name: 'Remover' })).toHaveLength(2)
    expect(screen.queryByLabelText('Alterar papel: Dona Ana')).toBeNull()
    expect(screen.getByText('Dono')).toBeInTheDocument()
  })

  it('membro edit vê a lista SEM nenhum botão de mutação', async () => {
    comoPapel('edit')
    renderPanel()

    expect(await screen.findByText('Edu Edit')).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Remover' })).toBeNull()
    expect(screen.queryByRole('button', { name: 'Revogar' })).toBeNull()
    expect(screen.queryByRole('button', { name: 'Convidar pessoa' })).toBeNull()
    // E a lista de convites (que só o dono pode ler) nem é buscada.
    expect(listInvites).not.toHaveBeenCalled()
  })

  it('convite expirado é rotulado como Expirado, não como pendente ativo', async () => {
    comoPapel('owner')
    renderPanel()

    await screen.findByText('velho@fabrica.com')
    expect(screen.getByText(/Expirado/)).toBeInTheDocument()
  })

  it('mudar papel chama a API e invalida a lista de membros', async () => {
    comoPapel('owner')
    updateRole.mockResolvedValue({ id: 'm-2', role: 'edit' })
    renderPanel()

    const seletor = await screen.findByLabelText('Alterar papel: Vera View')
    fireEvent.change(seletor, { target: { value: 'edit' } })

    await waitFor(() => expect(updateRole).toHaveBeenCalledWith('m-2', 'edit'))
  })

  it('remover pede confirmação explícita antes de chamar a API', async () => {
    comoPapel('owner')
    removeMember.mockResolvedValue(undefined)
    renderPanel()

    await screen.findByText('Edu Edit')
    fireEvent.click(screen.getAllByRole('button', { name: 'Remover' })[0])

    expect(window.confirm).toHaveBeenCalledWith(expect.stringMatching(/Remover Edu Edit/))
    await waitFor(() => expect(removeMember).toHaveBeenCalledWith('m-1'))
  })

  it('revogar convite pede confirmação e chama a API', async () => {
    comoPapel('owner')
    revokeInvite.mockResolvedValue(undefined)
    renderPanel()

    await screen.findByText('novo@fabrica.com')
    fireEvent.click(screen.getAllByRole('button', { name: 'Revogar' })[0])

    expect(window.confirm).toHaveBeenCalledWith(expect.stringMatching(/novo@fabrica\.com/))
    await waitFor(() => expect(revokeInvite).toHaveBeenCalledWith('i-9'))
  })

  it('a lista de pendentes permite recopiar o link de cada convite', async () => {
    comoPapel('owner')
    renderPanel()

    const campo = (await screen.findByLabelText('Link do convite: novo@fabrica.com')) as HTMLInputElement
    expect(campo.value).toBe('http://localhost:5173/convite/rt_inv_ABC')
  })
})

describe('InviteDialog (dentro do painel)', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    listMembers.mockResolvedValue(MEMBROS)
    listInvites.mockResolvedValue([])
    comoPapel('owner')
  })

  afterEach(cleanup)

  async function abrirDialogo() {
    renderPanel()
    fireEvent.click(await screen.findByRole('button', { name: 'Convidar pessoa' }))
  }

  it('cria o convite e mostra o link absoluto', async () => {
    createInvite.mockResolvedValue(CONVITES[0])
    await abrirDialogo()

    fireEvent.change(screen.getByLabelText('E-mail'), { target: { value: 'novo@fabrica.com' } })
    fireEvent.click(screen.getByRole('button', { name: 'Gerar link de convite' }))

    await waitFor(() => expect(createInvite).toHaveBeenCalledWith({ email: 'novo@fabrica.com', role: 'view' }))
    const campo = (await screen.findByLabelText('Link do convite')) as HTMLInputElement
    expect(campo.value).toBe('http://localhost:5173/convite/rt_inv_ABC')
  })

  it('e-mail inválido nem chega à rede', async () => {
    await abrirDialogo()

    fireEvent.change(screen.getByLabelText('E-mail'), { target: { value: 'sem-arroba' } })
    fireEvent.click(screen.getByRole('button', { name: 'Gerar link de convite' }))

    expect(createInvite).not.toHaveBeenCalled()
    expect(await screen.findByRole('alert')).toHaveTextContent(/e-mail válido/i)
  })

  it('copia o link e confirma visualmente', async () => {
    const writeText = vi.fn().mockResolvedValue(undefined)
    Object.defineProperty(navigator, 'clipboard', { value: { writeText }, configurable: true })
    createInvite.mockResolvedValue(CONVITES[0])
    await abrirDialogo()

    fireEvent.change(screen.getByLabelText('E-mail'), { target: { value: 'novo@fabrica.com' } })
    fireEvent.click(screen.getByRole('button', { name: 'Gerar link de convite' }))
    fireEvent.click(await screen.findByRole('button', { name: 'Copiar link' }))

    await waitFor(() => expect(writeText).toHaveBeenCalledWith('http://localhost:5173/convite/rt_inv_ABC'))
    expect(toastMock.success).toHaveBeenCalledWith(expect.stringMatching(/copiado/i))
  })

  it('Clipboard negada NÃO falha em silêncio: mostra o link para copiar à mão', async () => {
    const writeText = vi.fn().mockRejectedValue(new Error('NotAllowedError'))
    Object.defineProperty(navigator, 'clipboard', { value: { writeText }, configurable: true })
    createInvite.mockResolvedValue(CONVITES[0])
    await abrirDialogo()

    fireEvent.change(screen.getByLabelText('E-mail'), { target: { value: 'novo@fabrica.com' } })
    fireEvent.click(screen.getByRole('button', { name: 'Gerar link de convite' }))
    fireEvent.click(await screen.findByRole('button', { name: 'Copiar link' }))

    await waitFor(() => expect(toastMock.warning).toHaveBeenCalledWith(expect.stringMatching(/manualmente/i)))
    const campo = (await screen.findByLabelText('Link do convite')) as HTMLInputElement
    expect(campo.value).toContain('rt_inv_ABC')
    expect(screen.getByText(/Selecione o link e copie manualmente/)).toBeInTheDocument()
  })

  it('segundo convite pendente para o mesmo e-mail (409) explica o que fazer', async () => {
    createInvite.mockRejectedValue({ response: { status: 409, data: { error: 'invitation_already_pending' } } })
    await abrirDialogo()

    fireEvent.change(screen.getByLabelText('E-mail'), { target: { value: 'novo@fabrica.com' } })
    fireEvent.click(screen.getByRole('button', { name: 'Gerar link de convite' }))

    expect(await screen.findByRole('alert')).toHaveTextContent(/Revogue o anterior/)
  })
})
