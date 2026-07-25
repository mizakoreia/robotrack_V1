import { test, expect, SEED } from '../fixtures/session'
import { axeFindings, describeFindings, setTheme, type Theme } from '../a11y/axe'

// quality-and-accessibility 5.6 (§Accessibility / D-QA-3) — o gate axe-core em 8
// telas × 2 temas + uma passagem com o modal de avanço ABERTO. `incomplete` de
// contraste conta como NÃO-aprovação (ver `a11y/axe.ts`): o tema claro é o menos
// usado e é onde a regressão de contraste mora, e as telas são todas de vidro.
//
// Estado do SEED `[convite]` (ids fixos). O dono é `owner` do WS-E2E, então a
// primeira carga auto-seleciona o próprio workspace — não precisa de
// `entrarNoWorkspace`.

// As 8 superfícies. Rotas com id vêm do seed determinístico (nunca navegadas por
// clique — D-QA-2: o estado é semeado, o teste só audita).
const TELAS: { nome: string; path: string }[] = [
  { nome: 'Visão Geral', path: '/' },
  { nome: 'Projeto', path: `/projeto/${SEED.project.id}` },
  { nome: 'Célula', path: `/projeto/${SEED.project.id}/celula/${SEED.cell.id}` },
  { nome: 'Robô', path: `/robo/${SEED.robot.id}` },
  { nome: 'Minhas Tarefas', path: '/minhas-tarefas' },
  { nome: 'Relatório', path: '/relatorio' },
  { nome: 'Configurações', path: '/configuracoes' },
  { nome: 'Equipe', path: '/configuracoes/equipe' },
]
const TEMAS: Theme[] = ['dark', 'light']

test.describe('5.6 — gate axe-core (8 telas × 2 temas)', () => {
  for (const tela of TELAS) {
    for (const tema of TEMAS) {
      test(`${tela.nome} [${tema}] sem violação nem incomplete de contraste`, async ({ ownerPage }) => {
        await ownerPage.goto(tela.path)
        // Espera por ESTADO, não por tempo: o shell autenticado montou.
        await expect(ownerPage.getByRole('link', { name: 'Visão Geral' })).toBeVisible()
        await setTheme(ownerPage, tema)

        const findings = await axeFindings(ownerPage)
        expect(findings, `${tela.nome} [${tema}]:\n${describeFindings(findings)}`).toHaveLength(0)
      })
    }
  }

  test('Robô com o modal de avanço ABERTO permanece limpo (claro)', async ({ ownerPage }) => {
    await ownerPage.goto(`/robo/${SEED.robot.id}`)
    const linha = ownerPage.getByRole('row', { name: new RegExp(SEED.task.desc) })
    const slider = linha.getByRole('slider', { name: 'Progresso da tarefa' })
    await expect(slider).toBeVisible()

    // Abre o modal de avanço: arrasta e SOLTA (a UX nova abre a observação no fim
    // do arraste). Auditar o overlay é o ponto — é onde o foco preso e o contraste
    // de vidro precisam valer.
    await slider.fill('50')
    await slider.dispatchEvent('pointerup')
    const modal = ownerPage.getByRole('dialog', { name: 'Registrar avanço' })
    await expect(modal).toBeVisible()

    await setTheme(ownerPage, 'light')
    const findings = await axeFindings(ownerPage)
    expect(findings, `Robô + modal [light]:\n${describeFindings(findings)}`).toHaveLength(0)
  })

  // O gate não pode ser VAZIO: um axe que nunca reprova é axe desligado (D-QA-3).
  // Planta um botão SEM nome acessível (violação `button-name`, impacto crítico) e
  // afirma que o gate o pega — prova viva de que a ausência de achados nos testes
  // acima é sinal, não silêncio.
  test('o gate PEGA uma violação crítica plantada (prova de não-vacuidade)', async ({ ownerPage }) => {
    await ownerPage.goto('/')
    await expect(ownerPage.getByRole('link', { name: 'Visão Geral' })).toBeVisible()
    await ownerPage.evaluate(() => {
      const b = document.createElement('button')
      b.id = '__axe_probe__' // só ícone, sem texto nem aria-label → button-name
      b.innerHTML = '<svg width="10" height="10"></svg>'
      document.body.appendChild(b)
    })
    const findings = await axeFindings(ownerPage)
    expect(findings.map((f) => f.id)).toContain('button-name')
  })
})
