import { describe, expect, it, vi, afterEach } from 'vitest'
import { render, screen, fireEvent, waitFor } from '@testing-library/react'
import { FactoryResetModal } from '@/features/settings/FactoryResetModal'
import { UtilitiesPanel } from '@/features/settings/UtilitiesPanel'
import { backupApi, factoryResetApi } from '@/lib/api/endpoints'
import { queryClient } from '@/lib/queryClient'
import { flags } from '@/lib/flags'
import { useWorkspaceStore } from '@/store/workspaceStore'

// workspace-settings 5.8 (§3.11, D-RESET-GATE) — o modal do reset: frase trava o
// botão, o EXPORT roda ANTES do reset (não existe caminho sem backup), e a falha
// de cada etapa mostra o erro certo sem executar a seguinte.
afterEach(() => {
  vi.restoreAllMocks()
  flags.factoryReset = false
})

const NAME = 'Fábrica Alfa'

function renderModal() {
  return render(<FactoryResetModal open onClose={() => {}} workspaceName={NAME} />)
}

describe('FactoryResetModal (5.8)', () => {
  it('botão desabilitado até a frase casar EXATAMENTE (caixa sensível)', () => {
    renderModal()
    const confirmar = screen.getByRole('button', { name: 'Fazer backup e resetar' })
    expect(confirmar).toBeDisabled()

    fireEvent.change(screen.getByPlaceholderText('Nome exato do workspace'), {
      target: { value: 'fábrica alfa' },
    })
    expect(confirmar).toBeDisabled() // caixa errada não habilita

    fireEvent.change(screen.getByPlaceholderText('Nome exato do workspace'), {
      target: { value: ` ${NAME} ` }, // bordas são toleradas (strip)
    })
    expect(confirmar).toBeEnabled()
  })

  it('confirmar: export ANTES do reset, reset com frase+backupId, cache limpo, "concluído"', async () => {
    const ordem: string[] = []
    vi.spyOn(backupApi, 'create').mockImplementation(async () => {
      ordem.push('backup')
      return { json: '{"_rt":{}}', backupId: 'b-9', status: 200 }
    })
    vi.spyOn(factoryResetApi, 'create').mockImplementation(async () => {
      ordem.push('reset')
      return { projects_count: 2 }
    })
    const cancel = vi.spyOn(queryClient, 'cancelQueries').mockResolvedValue()
    const clear = vi.spyOn(queryClient, 'clear').mockImplementation(() => {})

    renderModal()
    fireEvent.change(screen.getByPlaceholderText('Nome exato do workspace'), { target: { value: NAME } })
    fireEvent.click(screen.getByRole('button', { name: 'Fazer backup e resetar' }))

    expect(await screen.findByText(/Reset concluído/)).toBeInTheDocument()
    expect(ordem).toEqual(['backup', 'reset']) // backup SEMPRE primeiro
    expect(factoryResetApi.create).toHaveBeenCalledWith(NAME, 'b-9')
    expect(cancel).toHaveBeenCalled()
    expect(clear).toHaveBeenCalled()
  })

  it('backup falhou → alerta e o reset NÃO é chamado', async () => {
    vi.spyOn(backupApi, 'create').mockRejectedValue(new Error('boom'))
    const reset = vi.spyOn(factoryResetApi, 'create')

    renderModal()
    fireEvent.change(screen.getByPlaceholderText('Nome exato do workspace'), { target: { value: NAME } })
    fireEvent.click(screen.getByRole('button', { name: 'Fazer backup e resetar' }))

    expect(await screen.findByRole('alert')).toHaveTextContent('o reset NÃO foi executado')
    expect(reset).not.toHaveBeenCalled()
  })

  it('backup 202 (assíncrono) → avisa e NÃO reseta (o gate exige completed)', async () => {
    vi.spyOn(backupApi, 'create').mockResolvedValue({ json: null, backupId: 'b-2', status: 202 })
    const reset = vi.spyOn(factoryResetApi, 'create')

    renderModal()
    fireEvent.change(screen.getByPlaceholderText('Nome exato do workspace'), { target: { value: NAME } })
    fireEvent.click(screen.getByRole('button', { name: 'Fazer backup e resetar' }))

    expect(await screen.findByRole('alert')).toHaveTextContent(/geração em andamento/)
    expect(reset).not.toHaveBeenCalled()
  })

  it('reset recusado (422) → alerta próprio; o backup já tinha sido baixado', async () => {
    vi.spyOn(backupApi, 'create').mockResolvedValue({ json: '{}', backupId: 'b-1', status: 200 })
    vi.spyOn(factoryResetApi, 'create').mockRejectedValue({ response: { status: 422 } })

    renderModal()
    fireEvent.change(screen.getByPlaceholderText('Nome exato do workspace'), { target: { value: NAME } })
    fireEvent.click(screen.getByRole('button', { name: 'Fazer backup e resetar' }))

    expect(await screen.findByRole('alert')).toHaveTextContent('recusado pelo servidor')
  })
})

describe('UtilitiesPanel — gating por flag (5.8)', () => {
  it('flag desligada: o botão de reset NÃO existe', () => {
    flags.factoryReset = false
    render(<UtilitiesPanel />)
    expect(screen.queryByRole('button', { name: 'Resetar workspace…' })).not.toBeInTheDocument()
  })

  it('flag ligada: botão presente; clicar abre o modal com o nome do workspace', () => {
    flags.factoryReset = true
    useWorkspaceStore.setState({
      currentWorkspaceId: 'w1',
      workspaces: [{ id: 'w1', name: NAME, role: 'owner' }],
    })
    render(<UtilitiesPanel />)
    fireEvent.click(screen.getByRole('button', { name: 'Resetar workspace…' }))
    expect(screen.getByText(new RegExp(NAME))).toBeInTheDocument()
  })
})
