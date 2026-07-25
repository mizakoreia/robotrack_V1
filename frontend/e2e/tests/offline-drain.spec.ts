import { test, expect, SEED, entrarNoWorkspace, apiBase } from '../fixtures/session'

// quality-and-accessibility 7.3 (Fluxo 2b, D7/D8) — drenagem e ORDEM. Três avanços
// offline, recarregamento da página AINDA offline (a fila sobrevive ao ciclo de
// vida da aba — trocar de app no celular não pode perder trabalho), a rede volta, e
// o servidor converge com 3 `task_advances` cujo `recorded_at` (o carimbo do
// enfileiramento) é anterior ao `created_at` (a inserção no servidor, pós-reconexão).

test.describe('7.3 — drenagem offline e ordem', () => {
  test('3 avanços offline sobrevivem ao reload e convergem 3 no servidor', async ({ memberPage, baseURL }) => {
    await entrarNoWorkspace(memberPage, SEED.workspace.id)
    await memberPage.goto(`/robo/${SEED.robot.id}`)
    const slider = () => memberPage.getByRole('row', { name: new RegExp(SEED.task.desc) }).getByRole('slider', { name: 'Progresso da tarefa' })
    await expect(slider()).toHaveValue(String(SEED.task.progress)) // 40

    await memberPage.context().setOffline(true)

    // Três avanços encadeados: 40→50→60→70. Cada um enfileira (offline).
    for (const alvo of ['50', '60', '70']) {
      await slider().fill(alvo)
      await slider().dispatchEvent('pointerup')
      const modal = memberPage.getByRole('dialog', { name: 'Registrar avanço' })
      await modal.getByLabel(/Comentário/).fill(`avanço offline para ${alvo}`)
      await modal.getByRole('button', { name: 'Registrar' }).click()
      await expect(modal).toHaveCount(0)
    }
    await expect(slider()).toHaveValue('70')
    await expect(memberPage.getByText('Alterações pendentes')).toBeVisible()

    // Recarrega AINDA offline: o overlay é derivado da FILA (IndexedDB), então
    // sobrevive ao remount — os 70 continuam lá, sem servidor.
    await memberPage.reload()
    await expect(slider()).toHaveValue('70')

    // Momento da reconexão: todo `recorded_at` (enfileirado ANTES) tem de ser < isto.
    const reconnectAt = new Date().toISOString()
    await memberPage.context().setOffline(false)

    // A fila drena em segundo plano; o indicador honesto passa a "Salvo".
    await expect(memberPage.getByText('Salvo', { exact: true })).toBeVisible({ timeout: 15_000 })

    // O SERVIDOR convergiu: 3 avanços, cada `recorded_at` anterior à reconexão
    // (prova de que `recorded_at` < `created_at`, sem depender do payload expor os
    // dois). `expect.poll` espera por ESTADO (não por tempo).
    const token = await memberPage.evaluate(() => {
      const raw = localStorage.getItem('robotrack.session')
      return raw ? ((JSON.parse(raw) as { accessToken?: string }).accessToken ?? '') : ''
    })
    const fetchAdvances = async () => {
      const res = await memberPage.request.get(`${apiBase(baseURL)}/api/v1/tasks/${SEED.task.id}/advances`, {
        headers: { Authorization: `Bearer ${token}`, 'X-Workspace-Id': SEED.workspace.id },
      })
      if (!res.ok()) return [] as { recorded_at: string }[]
      const body = (await res.json()) as { data?: { recorded_at: string }[] } | { recorded_at: string }[]
      return Array.isArray(body) ? body : (body.data ?? [])
    }
    await expect.poll(async () => (await fetchAdvances()).length, { timeout: 15_000 }).toBe(3)

    const advances = await fetchAdvances()
    for (const a of advances) {
      expect(new Date(a.recorded_at).getTime()).toBeLessThan(new Date(reconnectAt).getTime())
    }
  })
})

// 7.3 sub-caso — "robô criado offline sincroniza ANTES do avanço na tarefa dele".
// O produtor de fila + overlay do BatchRobotWizard é um SEAM ABERTO de `offline-pwa`
// (o `useCreateRobot` de robô único está sem uso; a criação em LOTE não tem produtor
// nem overlay — cenário raro, feito na mesa com sinal). `fixme` explícito até a
// fiação: rodar isto hoje reprovaria por capacidade ausente, não por regressão.
test.fixme('7.3 — robô criado offline sincroniza antes do avanço (seam offline-pwa aberto)', () => {})
