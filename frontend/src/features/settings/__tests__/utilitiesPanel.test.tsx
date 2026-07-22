import { describe, expect, it, vi, afterEach } from 'vitest'
import { render, screen, fireEvent } from '@testing-library/react'
import { UtilitiesPanel } from '@/features/settings/UtilitiesPanel'
import { backupApi } from '@/lib/api/endpoints'

// workspace-settings 4.5 (§3.11, D-EXP) — o botão de export: dispara o backup,
// captura o backupId (para o reset), e distingue o caminho síncrono (download +
// "gerado") do assíncrono (202 → aviso).
afterEach(() => vi.restoreAllMocks())

describe('UtilitiesPanel (4.5)', () => {
  it('exportar chama a API, baixa o arquivo e informa "gerado"; repassa o backupId', async () => {
    vi.spyOn(backupApi, 'create').mockResolvedValue({ json: '{"_rt":{}}', backupId: 'b-1', status: 200 })
    const onBackup = vi.fn()
    render(<UtilitiesPanel onBackup={onBackup} />)
    fireEvent.click(screen.getByRole('button', { name: 'Exportar backup' }))
    expect(await screen.findByText('Backup gerado e baixado.')).toBeInTheDocument()
    expect(onBackup).toHaveBeenCalledWith('b-1')
  })

  it('202 (backup grande) avisa geração assíncrona, sem download', async () => {
    vi.spyOn(backupApi, 'create').mockResolvedValue({ json: null, backupId: 'b-2', status: 202 })
    render(<UtilitiesPanel />)
    fireEvent.click(screen.getByRole('button', { name: 'Exportar backup' }))
    expect(await screen.findByText(/geração em andamento/)).toBeInTheDocument()
  })

  it('erro mostra alerta acionável', async () => {
    vi.spyOn(backupApi, 'create').mockRejectedValue({ response: { status: 500 } })
    render(<UtilitiesPanel />)
    fireEvent.click(screen.getByRole('button', { name: 'Exportar backup' }))
    expect(await screen.findByRole('alert')).toHaveTextContent('Não foi possível gerar o backup.')
  })
})
