import { describe, expect, it, vi, beforeEach, afterEach } from 'vitest'
import { render, screen, fireEvent, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import type { ReactNode } from 'react'
import { CatalogPanel, FilterEditor } from '@/features/settings/CatalogPanel'
import { taskTemplatesApi, metaApi, type TaskTemplateDTO } from '@/lib/api/endpoints'
import { useWorkspaceStore } from '@/store/workspaceStore'

// workspace-settings 3.2–3.6 (§3.9, §1.3, D-CATALOG-FILTER) — a tela do catálogo: os
// três caminhos do editor de filtro (a requisição NUNCA carrega "Misto / Geral"), a
// ordem lexicográfica por categoria, o modo leitura de `view`, e a exclusão.
const APPS = ['Misto / Geral', 'Solda Ponto', 'Handling', 'Sealing', 'Outros']

function tpl(over: Partial<TaskTemplateDTO> = {}): TaskTemplateDTO {
  return { id: 't1', cat: 'A. Hardware', desc: 'Fixar base', weight: 1, appFilters: [], ...over }
}

function wrap() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } })
  return ({ children }: { children: ReactNode }) => <QueryClientProvider client={client}>{children}</QueryClientProvider>
}

beforeEach(() => {
  useWorkspaceStore.setState({
    workspaces: [{ id: 'betim', name: 'Betim', role: 'owner' }],
    currentWorkspaceId: 'betim', currentRoleLabel: 'owner',
  })
  vi.spyOn(metaApi, 'robotApplications').mockResolvedValue(APPS)
})
afterEach(() => vi.restoreAllMocks())

describe('FilterEditor — os três caminhos (D-CATALOG-FILTER)', () => {
  it('marcar "Misto / Geral" envia []', () => {
    const onChange = vi.fn()
    render(<FilterEditor apps={APPS} value={['Handling']} onChange={onChange} />)
    fireEvent.click(screen.getByLabelText('Misto / Geral'))
    expect(onChange).toHaveBeenCalledWith([])
  })

  it('marcar uma aplicação específica (partindo de []) desmarca Misto e envia [app]', () => {
    const onChange = vi.fn()
    render(<FilterEditor apps={APPS} value={[]} onChange={onChange} />)
    fireEvent.click(screen.getByLabelText('Handling'))
    expect(onChange).toHaveBeenCalledWith(['Handling'])
  })

  it('sobre ["Handling","Solda Ponto"], marcar Misto vira []', () => {
    const onChange = vi.fn()
    render(<FilterEditor apps={APPS} value={['Handling', 'Solda Ponto']} onChange={onChange} />)
    fireEvent.click(screen.getByLabelText('Misto / Geral'))
    expect(onChange).toHaveBeenCalledWith([])
  })
})

describe('CatalogPanel (3.2/3.5/3.6)', () => {
  it('agrupa por categoria em ordem lexicográfica (A. antes de B. antes de C.)', async () => {
    vi.spyOn(taskTemplatesApi, 'list').mockResolvedValue([
      tpl({ id: '3', cat: 'C. Testes', desc: 'TCP' }),
      tpl({ id: '1', cat: 'A. Hardware', desc: 'Base' }),
      tpl({ id: '2', cat: 'B. Software', desc: 'Carga' }),
    ])
    render(<CatalogPanel canWrite />, { wrapper: wrap() })
    await screen.findByText('Base')
    const cats = screen.getAllByText(/^[ABC]\./).map((n) => n.textContent)
    expect(cats).toEqual(['A. Hardware', 'B. Software', 'C. Testes'])
  })

  it('view: sem coluna excluir, sem form de adição, filtro não editável', async () => {
    vi.spyOn(taskTemplatesApi, 'list').mockResolvedValue([tpl({ desc: 'Base' })])
    render(<CatalogPanel canWrite={false} />, { wrapper: wrap() })
    await screen.findByText('Base')
    expect(screen.queryByLabelText('Excluir Base')).toBeNull()
    expect(screen.queryByLabelText('Categoria (ex.: A. Hardware)')).toBeNull()
    expect(screen.queryByLabelText('Editar aplicações')).toBeNull()
  })

  it('adicionar envia weight=1 e o filtro escolhido; a requisição não contém "Misto / Geral"', async () => {
    vi.spyOn(taskTemplatesApi, 'list').mockResolvedValue([])
    const create = vi.spyOn(taskTemplatesApi, 'create').mockResolvedValue(tpl())
    render(<CatalogPanel canWrite />, { wrapper: wrap() })
    fireEvent.change(await screen.findByLabelText('Categoria (ex.: A. Hardware)'), { target: { value: 'A. Hardware' } })
    fireEvent.change(screen.getByLabelText('Descrição da tarefa'), { target: { value: 'Nova' } })
    fireEvent.click(screen.getByLabelText('Handling')) // filtro específico → []→['Handling']
    fireEvent.click(screen.getByRole('button', { name: 'Adicionar tarefa-base' }))
    await waitFor(() => expect(create).toHaveBeenCalled())
    const arg = create.mock.calls[0][0]
    expect(arg).toMatchObject({ cat: 'A. Hardware', desc: 'Nova', weight: 1, appFilters: ['Handling'] })
    expect(JSON.stringify(create.mock.calls)).not.toContain('Misto / Geral')
  })

  it('excluir pede confirmação e só então chama a API', async () => {
    vi.spyOn(taskTemplatesApi, 'list').mockResolvedValue([tpl({ id: 'z', desc: 'TCP Check' })])
    const destroy = vi.spyOn(taskTemplatesApi, 'destroy').mockResolvedValue(undefined as never)
    render(<CatalogPanel canWrite />, { wrapper: wrap() })
    fireEvent.click(await screen.findByLabelText('Excluir TCP Check'))
    expect(destroy).not.toHaveBeenCalled()
    fireEvent.click(screen.getByRole('button', { name: 'Confirmar exclusão' }))
    await waitFor(() => expect(destroy).toHaveBeenCalledWith('z'))
  })
})
