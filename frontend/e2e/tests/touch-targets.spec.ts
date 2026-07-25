import { test, expect, SEED } from '../fixtures/session'
import { auditTouchTargets, describeTouch, MIN_TOUCH_PX } from '../a11y/touch-targets'

// quality-and-accessibility 5.5 (`PRODUCT.md §Users`) — o auditor de alvo de toque
// nas telas que o operário usa no CELULAR (375×812). O layout mobile (cartões <md)
// é o alvo real: 32px é requisito de ambiente (luva, escuro do galpão). O estado
// vem do SEED `[convite]` — o dono é `owner` do WS-E2E (auto-seleção na 1ª carga).

test.use({ viewport: { width: 375, height: 812 } })

const TELAS: { nome: string; path: string }[] = [
  { nome: 'Visão Geral', path: '/' },
  { nome: 'Robô', path: `/robo/${SEED.robot.id}` },
  { nome: 'Minhas Tarefas', path: '/minhas-tarefas' },
  { nome: 'Equipe', path: '/configuracoes/equipe' },
]

test.describe('5.5 — auditor de alvo de toque (375×812)', () => {
  for (const tela of TELAS) {
    test(`${tela.nome}: todo controle tocável ≥ ${MIN_TOUCH_PX}px, sem sobreposição estendida`, async ({
      ownerPage,
    }) => {
      await ownerPage.goto(tela.path)
      // Espera por ESTADO (o shell montou) antes de medir o layout.
      await expect(ownerPage.getByRole('link', { name: 'Visão Geral' })).toBeVisible()

      const v = await auditTouchTargets(ownerPage)
      expect(v, `${tela.nome}:\n${describeTouch(v)}`).toHaveLength(0)
    })
  }

  // O auditor não pode ser VAZIO: planta um botão de 20×20px (abaixo dos 32) e
  // afirma que ele é PEGO — prova de que "0 achados" acima é sinal, não silêncio.
  test('o auditor PEGA um alvo pequeno plantado (prova de não-vacuidade)', async ({ ownerPage }) => {
    await ownerPage.goto('/')
    await expect(ownerPage.getByRole('link', { name: 'Visão Geral' })).toBeVisible()
    await ownerPage.evaluate(() => {
      const b = document.createElement('button')
      b.setAttribute('aria-label', 'alvo minúsculo plantado')
      b.style.cssText = 'position:fixed;top:0;left:0;width:20px;height:20px'
      document.body.appendChild(b)
    })
    const v = await auditTouchTargets(ownerPage)
    expect(v.some((x) => x.reason === 'pequeno' && x.label.includes('minúsculo'))).toBe(true)
  })
})
