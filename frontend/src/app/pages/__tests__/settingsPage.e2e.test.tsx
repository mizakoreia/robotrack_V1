import { describe, expect, it, vi, beforeEach, afterEach } from 'vitest'
import { render, screen, fireEvent, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import type { ReactNode } from 'react'
import { SettingsPage } from '@/app/pages/SettingsPage'
import { ThemeProvider } from '@/components/ThemeProvider'
import {
  peopleApi, taskTemplatesApi, metaApi, backupApi, factoryResetApi, auditLogsApi,
  type PersonDTO, type AuditLogDTO,
} from '@/lib/api/endpoints'
import { flags } from '@/lib/flags'
import { useWorkspaceStore } from '@/store/workspaceStore'
import { useThemeStore } from '@/store/themeStore'

// workspace-settings 6.4 (§3.9, §3.11, D12) — o E2E de fechamento da tela de
// Configurações: chip → filtro "Misto / Geral" (a requisição NUNCA leva a string)
// → exportar → resetar com a frase → auditoria PRESERVADA com o registro novo no
// topo — e a tela funciona nos DOIS temas (o toggle do painel Aparência aplica a
// classe na raiz; escuro é o :root, claro é `.light` — a convenção entregue).
const PRIOR: AuditLogDTO = {
  id: 'a1', msg: 'Em [R], Ana concluiu a tarefa "Antiga" com 100%.',
  ts: '2026-07-20T10:00:00Z', ts_local: '20/07/2026 07:00', by_name: 'Ana', event_type: 'task_completed',
}
const RESET_LOG: AuditLogDTO = {
  id: 'a2', msg: 'Ana executou o reset de fábrica do workspace. Projetos removidos: 2.',
  ts: '2026-07-22T10:00:00Z', ts_local: '22/07/2026 07:00', by_name: 'Ana', event_type: 'workspace_reset',
}

function wrap() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } })
  return ({ children }: { children: ReactNode }) => (
    <QueryClientProvider client={client}><ThemeProvider>{children}</ThemeProvider></QueryClientProvider>
  )
}

let people: PersonDTO[]
let logs: AuditLogDTO[]

beforeEach(() => {
  people = []
  logs = [PRIOR]
  flags.factoryReset = true
  useThemeStore.setState({ theme: 'dark' })
  useWorkspaceStore.setState({
    workspaces: [{ id: 'w1', name: 'Betim', role: 'owner' }],
    currentWorkspaceId: 'w1', currentRoleLabel: 'owner',
  })
  vi.spyOn(peopleApi, 'list').mockImplementation(async () => [...people])
  vi.spyOn(peopleApi, 'create').mockImplementation(async ({ name }: any) => {
    const p = { id: `p-${people.length + 1}`, name, has_account: false }
    people.push(p)
    return p
  })
  vi.spyOn(taskTemplatesApi, 'list').mockResolvedValue([
    { id: 't1', cat: 'A. Hardware', desc: 'Fixar base', weight: 1, appFilters: ['Handling'] },
  ])
  vi.spyOn(taskTemplatesApi, 'update').mockResolvedValue({} as any)
  vi.spyOn(metaApi, 'robotApplications').mockResolvedValue(['Misto / Geral', 'Handling', 'Sealing'])
  vi.spyOn(auditLogsApi, 'list').mockImplementation(async () => [...logs])
})
afterEach(() => {
  vi.restoreAllMocks()
  flags.factoryReset = false
  document.documentElement.classList.remove('light')
})

describe('SettingsPage — E2E de fechamento (6.4)', () => {
  it('chip → Misto/Geral → exportar+resetar → auditoria preservada, nos dois temas', async () => {
    const ordem: string[] = []
    vi.spyOn(backupApi, 'create').mockImplementation(async () => {
      ordem.push('backup')
      return { json: '{"_rt":{}}', backupId: 'b-1', status: 200 }
    })
    vi.spyOn(factoryResetApi, 'create').mockImplementation(async () => {
      ordem.push('reset')
      logs = [RESET_LOG, PRIOR] // o servidor gravou o registro NA transação do reset
      return { projects_count: 2 }
    })

    render(<SettingsPage />, { wrapper: wrap() })

    // 1) adicionar chip
    fireEvent.change(await screen.findByPlaceholderText('Nome da pessoa'), { target: { value: 'Bia Campo' } })
    fireEvent.click(screen.getByRole('button', { name: 'Adicionar' }))
    await screen.findByText('Bia Campo')

    // 2) filtro → Misto / Geral; a requisição NUNCA contém a string
    await screen.findByText('Fixar base')
    fireEvent.click(screen.getByLabelText('Editar aplicações'))
    const misto = screen
      .getAllByLabelText('Misto / Geral')
      .find((el) => (el as HTMLInputElement).type === 'checkbox') as HTMLInputElement
    fireEvent.click(misto)
    await waitFor(() => expect(taskTemplatesApi.update).toHaveBeenCalled())
    expect(JSON.stringify(vi.mocked(taskTemplatesApi.update).mock.calls)).not.toContain('Misto / Geral')

    // 3) exportar + resetar (backup SEMPRE antes; frase exata)
    fireEvent.click(screen.getByRole('button', { name: 'Resetar workspace…' }))
    fireEvent.change(screen.getByPlaceholderText('Nome exato do workspace'), { target: { value: 'Betim' } })
    fireEvent.click(screen.getByRole('button', { name: 'Fazer backup e resetar' }))
    await screen.findByText(/Reset concluído/)
    expect(ordem).toEqual(['backup', 'reset'])

    // 4) auditoria: preservada + o reset é o PRIMEIRO item (tema escuro)
    fireEvent.click(screen.getByRole('button', { name: 'Ver log de auditoria' }))
    await screen.findByText(RESET_LOG.msg)
    const corpo = document.body.textContent ?? ''
    expect(corpo.indexOf(RESET_LOG.msg)).toBeGreaterThan(-1)
    expect(corpo.indexOf(RESET_LOG.msg)).toBeLessThan(corpo.indexOf(PRIOR.msg)) // mais recente primeiro
    expect(document.documentElement.classList.contains('light')).toBe(false) // escuro = :root

    // 5) tema claro: toggle aplica `.light` e o conteúdo segue lá
    fireEvent.click(screen.getByRole('button', { name: 'Claro' }))
    await waitFor(() => expect(document.documentElement.classList.contains('light')).toBe(true))
    expect(screen.getByText(RESET_LOG.msg)).toBeInTheDocument()
    expect(screen.getByText(PRIOR.msg)).toBeInTheDocument()
  })

  it('view: sem Utilitários (reset/backup fora do DOM), auditoria ACESSÍVEL', async () => {
    useWorkspaceStore.setState({ currentRoleLabel: 'view' })
    render(<SettingsPage />, { wrapper: wrap() })
    await screen.findByText('Fixar base')
    expect(screen.queryByRole('button', { name: 'Exportar backup' })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Resetar workspace…' })).not.toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: 'Ver log de auditoria' }))
    await screen.findByText(PRIOR.msg)
  })
})

describe('AppearancePanel — degradação (6.1)', () => {
  it('armazenamento bloqueado: avisa uma vez, sem exceção; toggle segue na sessão', async () => {
    const { AppearancePanel } = await import('@/features/settings/AppearancePanel')
    vi.spyOn(Storage.prototype, 'setItem').mockImplementation(() => {
      throw new Error('blocked')
    })
    render(<AppearancePanel />)
    expect(screen.getByRole('status')).toHaveTextContent(/vale só nesta sessão/)
    fireEvent.click(screen.getByRole('button', { name: 'Claro' })) // não lança
    expect(useThemeStore.getState().theme).toBe('light')
  })
})
