import { test, expect, SEED } from '../fixtures/session'

// quality-and-accessibility 7.6 (Fluxo 5, §3.8 / D15) — o Protocolo de
// Comissionamento sobre `rt:seed:e2e[relatorio]`: distribuição 18/9/11/2 sobre total
// 40, as DUAS métricas ROTULADAS (exibir dois percentuais sem dizer qual é qual é
// indefensável na frente de quem assina), o identificador `RT-...`, e `ROB-VAZIO`
// presente (omitir um robô do escopo faria o cliente assinar um documento que não
// menciona um robô que existe).
//
// HANDOFF-CALIBRADO (DE-QA-B3.2): os PERCENTUAIS exatos (ponderado ~62% / contagem
// 45% = 18/40) e a paginação A4 (3 páginas, assinaturas na última) são afinados na
// EXECUÇÃO — a casa calibra o seed do relatório rodando o documento real
// (precedente `hierarchy-screens`), e a contagem de páginas A4 é do script dedicado
// `frontend/scripts/print-report.mjs` (printToPDF + pypdf), não deste fluxo de UI.
// O que este spec afirma é DETERMINÍSTICO do seed: distribuição, rótulos, id, vazio.

test.describe('7.6 — relatório A4', () => {
  test('distribuição 18/9/11/2, métricas rotuladas, id RT-, ROB-VAZIO e assinaturas', async ({ ownerPage }) => {
    await ownerPage.goto('/relatorio')
    // O documento congelado renderizou por inteiro (nunca pela metade — §4.3).
    await expect(ownerPage.locator('.rpt-doc')).toBeVisible()

    // Distribuição de status: os 4 glifos com as contagens EXATAS do seed.
    const dist = ownerPage.locator('.rpt-distribution')
    await expect(dist.getByRole('listitem').filter({ hasText: 'Concluído' })).toContainText(String(SEED.report.distribution.done)) // 18
    await expect(dist.getByRole('listitem').filter({ hasText: 'Em andamento' })).toContainText(String(SEED.report.distribution.inProgress)) // 9
    await expect(dist.getByRole('listitem').filter({ hasText: 'Pendente' })).toContainText(String(SEED.report.distribution.pending)) // 11
    await expect(dist.getByRole('listitem').filter({ hasText: 'N/A' })).toContainText(String(SEED.report.distribution.na)) // 2

    // A métrica PONDERADA vem ROTULADA (rótulo resolvido no servidor, D-R9).
    await expect(ownerPage.locator('.rpt-doc')).toContainText('progresso ponderado')

    // Identificador do documento no formato congelado RT-AAAAMMDD-HHMM. (O valor
    // exato exige relógio fixo — calibração de execução; aqui o FORMATO.)
    await expect(ownerPage.locator('.rpt-doc')).toContainText(/RT-\d{8}-\d{4}/)

    // ROB-VAZIO PRESENTE no documento (o robô sem tarefa não pode sumir do escopo).
    await expect(ownerPage.locator('.rpt-doc')).toContainText(SEED.report.empty.name)

    // Blocos de assinatura (na última página no papel — aqui, presença).
    await expect(ownerPage.locator('.rpt-doc')).toContainText('Comissionador')
    await expect(ownerPage.locator('.rpt-doc')).toContainText('Cliente / Aceite')
  })
})
