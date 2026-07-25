import { test, expect, SEED } from '../fixtures/session'

// quality-and-accessibility 4.4 (§Accessibility) — o percurso Visão Geral →
// Projeto → Célula → Robô → Minhas Tarefas → Relatório SÓ com teclado
// (Tab/setas/Enter/Escape). Falha se QUALQUER passo exigir mouse: a navegação por
// card usa `Enter` (o `EntityCard` inteiro é `role=button` operável por teclado), e
// o modal de avanço abre/fecha por teclado devolvendo o foco ao controle (4.3).
//
// O dono é `owner` do WS-E2E (auto-seleção na 1ª carga). Ids do SEED `[convite]`.
//
// NOTA de handoff: o número de `Tab` até cada card/controle depende da ordem de
// tabulação real — `tabPara` varre até achar o alvo por nome acessível (não fixa
// contagem). Como as slices 1-2, os locators se afinam na 1ª execução no par.

test.describe('4.4 — percurso de teclado (sem mouse)', () => {
  test('Visão Geral → Projeto → Célula → Robô → modal de avanço → Minhas Tarefas → Relatório', async ({
    ownerPage,
  }) => {
    await ownerPage.goto('/')
    // 1º expect ANTES de qualquer tecla — o shell autenticado montou.
    await expect(ownerPage.getByRole('link', { name: 'Visão Geral' })).toBeVisible()

    // — Visão Geral → Projeto: Enter no card do projeto —
    await tabPara(ownerPage, SEED.project.name)
    await ownerPage.keyboard.press('Enter')
    await expect(ownerPage).toHaveURL(new RegExp(`/projeto/${SEED.project.id}`))

    // — Projeto → Célula —
    await tabPara(ownerPage, SEED.cell.name)
    await ownerPage.keyboard.press('Enter')
    await expect(ownerPage).toHaveURL(new RegExp(`/celula/${SEED.cell.id}`))

    // — Célula → Robô —
    await tabPara(ownerPage, SEED.robot.name)
    await ownerPage.keyboard.press('Enter')
    await expect(ownerPage).toHaveURL(new RegExp(`/robo/${SEED.robot.id}`))

    // — Robô: abrir o modal de avanço SÓ com teclado e alterar o progresso —
    // Foca o slider da tarefa e pressiona ArrowRight: o `keyup` (fim do arraste)
    // abre a observação. Passo 5 → 40 vira 45.
    await tabPara(ownerPage, 'Progresso da tarefa')
    await ownerPage.keyboard.press('ArrowRight')
    const modal = ownerPage.getByRole('dialog', { name: 'Registrar avanço' })
    await expect(modal).toBeVisible()
    await expect(modal).toContainText('Para 45%')

    // Escape fecha e DEVOLVE o foco ao slider (contrato 4.3) — prova de teclado puro.
    await ownerPage.keyboard.press('Escape')
    await expect(modal).toHaveCount(0)
    const focoVoltou = await ownerPage.evaluate(
      () => (document.activeElement as HTMLElement | null)?.getAttribute('aria-label') === 'Progresso da tarefa',
    )
    expect(focoVoltou).toBe(true)

    // Reabre e COMPLETA o avanço por teclado (altera o estado da tarefa).
    await ownerPage.keyboard.press('ArrowRight') // 45 → 50
    await expect(modal).toContainText('Para 50%')
    await modal.getByLabel(/Comentário/).fill('percurso de teclado')
    await tabPara(ownerPage, 'Registrar')
    await ownerPage.keyboard.press('Enter')
    await expect(modal).toHaveCount(0)
    await expect(ownerPage.getByRole('slider', { name: 'Progresso da tarefa' }).first()).toHaveValue('50')

    // — Sidebar → Minhas Tarefas → Relatório (destinos como links, Enter) —
    await tabPara(ownerPage, 'Minhas Tarefas')
    await ownerPage.keyboard.press('Enter')
    await expect(ownerPage).toHaveURL(/\/minhas-tarefas/)

    await tabPara(ownerPage, 'Relatório')
    await ownerPage.keyboard.press('Enter')
    await expect(ownerPage).toHaveURL(/\/relatorio/)
  })
})

// Varre por `Tab` até que o elemento focado case o nome (aria-label ou texto), sem
// FIXAR contagem — a ordem de tabulação é detalhe de layout. Se não achar em `max`
// passos, falha nomeando o alvo (nunca um `waitForTimeout` — espera por ESTADO).
async function tabPara(page: import('@playwright/test').Page, alvo: string, max = 60): Promise<void> {
  for (let i = 0; i < max; i++) {
    await page.keyboard.press('Tab')
    const label = await page.evaluate(() => {
      const el = document.activeElement as HTMLElement | null
      if (!el) return ''
      return (el.getAttribute('aria-label') || el.textContent || '').trim().replace(/\s+/g, ' ')
    })
    if (label.includes(alvo)) return
  }
  throw new Error(`[e2e] Tab não alcançou "${alvo}" em ${max} passos (percurso de teclado 4.4).`)
}
