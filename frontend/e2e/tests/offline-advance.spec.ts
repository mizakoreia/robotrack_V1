import { test, expect, SEED, entrarNoWorkspace } from '../fixtures/session'

// quality-and-accessibility 7.2 (Fluxo 2a, §4.2 / `PRODUCT.md §Design Principles`)
// — avanço OFFLINE. Rede REALMENTE desligada (não um mock de `onLine`): registrar
// +10 sobre 40 mostra 50 (overlay otimista derivado da fila) e o indicador diz
// "Alterações pendentes", JAMAIS "Salvo". Desonestidade de estado aqui é o operário
// achar que registrou e perder o turno — o pior modo de falha do produto.

test.describe('7.2 — avanço offline (pendente, nunca Salvo)', () => {
  test('membro edit registra +10 offline: mostra 50, indicador pendente, nunca Salvo', async ({ memberPage }) => {
    await entrarNoWorkspace(memberPage, SEED.workspace.id)
    await memberPage.goto(`/robo/${SEED.robot.id}`)
    const linha = memberPage.getByRole('row', { name: new RegExp(SEED.task.desc) })
    const slider = linha.getByRole('slider', { name: 'Progresso da tarefa' })
    await expect(slider).toHaveValue(String(SEED.task.progress)) // 40, do seed

    // Rede REALMENTE desligada — o service worker segue servindo o app, mas o POST
    // do avanço não sai: o hook (`useRecordAdvance`) ENFILEIRA no IndexedDB.
    await memberPage.context().setOffline(true)

    await slider.fill('50')
    await slider.dispatchEvent('pointerup')
    const modal = memberPage.getByRole('dialog', { name: 'Registrar avanço' })
    await expect(modal).toContainText('Para 50%')
    await modal.getByLabel(/Comentário/).fill('cabo conferido, offline')
    await modal.getByRole('button', { name: 'Registrar' }).click()
    await expect(modal).toHaveCount(0)

    // Overlay OTIMISTA derivado da fila: a tarefa mostra 50 mesmo sem servidor.
    await expect(linha.getByRole('slider', { name: 'Progresso da tarefa' })).toHaveValue('50')

    // O indicador é HONESTO: "Alterações pendentes", e NUNCA "Salvo" (exact para
    // não casar "não salvo"). É a invariante de estado do PRODUCT.md.
    await expect(memberPage.getByText('Alterações pendentes')).toBeVisible()
    await expect(memberPage.getByText('Salvo', { exact: true })).toHaveCount(0)
  })
})
