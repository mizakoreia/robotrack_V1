import { test, expect, SEED, entrarNoWorkspace } from '../fixtures/session'

// quality-and-accessibility 7.1 (Fluxo 1, slice 2) — o convidado com papel `edit`
// REGISTRA um avanço no workspace do dono. Prova o que a slice 1 deixou em aberto:
// que a membership concedida pelo convite serve para TRABALHAR, não só aparecer numa
// lista. Requer `rt:seed:e2e[avanco]` (o convidado já é membro `edit`; a tarefa
// "Soldar ponto A" está a 40%) — o estado vem do SEED, não de outro teste ter
// rodado antes (D-QA-2).
//
// A UX do avanço mudou: NÃO há mais botões ±10. Arrastar o slider atualiza o valor
// ao vivo e a caixa de observação abre no FIM do arraste — o valor solto é o que o
// Registrar envia.

test.describe('Fluxo 1 slice 2 — o membro registra avanço', () => {
  test('membro edit leva a tarefa de 40% a 50%, e o valor sobrevive ao reload', async ({ memberPage }) => {
    // O membro é DONO de um workspace próprio, então a primeira carga o
    // selecionaria; aqui ele vem trabalhar no workspace do dono.
    await entrarNoWorkspace(memberPage, SEED.workspace.id)
    await memberPage.goto(`/robo/${SEED.robot.id}`)

    // Ancorado na LINHA da tarefa: a tabela tem uma linha por tarefa, e cada uma
    // tem seu próprio slider de mesmo nome acessível.
    const linha = memberPage.getByRole('row', { name: new RegExp(SEED.task.desc) })
    const slider = linha.getByRole('slider', { name: 'Progresso da tarefa' })
    await expect(slider).toHaveValue(String(SEED.task.progress)) // 40, do seed

    // Arrasta para 50 e SOLTA — é o soltar que abre a observação.
    await slider.fill('50')
    await expect(memberPage.getByRole('dialog')).toHaveCount(0) // arrastar não abre
    await slider.dispatchEvent('pointerup')

    const modal = memberPage.getByRole('dialog', { name: 'Registrar avanço' })
    await expect(modal).toContainText('Para 50%')
    // Abaixo de 100% o comentário é obrigatório (regra dura §2.4).
    await modal.getByLabel(/Comentário/).fill('solda do ponto A conferida')
    await modal.getByRole('button', { name: 'Registrar' }).click()

    // O servidor é a fonte da verdade: o slider volta a refletir o PERSISTIDO.
    await expect(modal).toHaveCount(0)
    await expect(linha.getByRole('slider', { name: 'Progresso da tarefa' })).toHaveValue('50')

    // Foi para o SERVIDOR, não é estado de tela: recarregar mantém os 50%.
    // (No mesmo teste de propósito — um teste separado dependeria da ORDEM de
    // execução para existir o avanço, e ordem entre testes é acoplamento.)
    await memberPage.reload()
    await expect(
      memberPage
        .getByRole('row', { name: new RegExp(SEED.task.desc) })
        .getByRole('slider', { name: 'Progresso da tarefa' }),
    ).toHaveValue('50')
  })
})
