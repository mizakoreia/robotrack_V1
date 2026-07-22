// Módulo ÚNICO dos textos da tabela de tarefas do robô (robot-task-table). Mesmo
// princípio de `advances.ts`/`invitations.ts`: as strings que o operador lê no
// galpão ficam num lugar só. Os DOIS avisos (D-RTT-6/7) e seus rótulos acessíveis
// moram aqui — a condição que os dispara é derivada na célula, mas a PALAVRA é
// spec traduzida, não literal solto no componente.

export const robotTaskText = {
  // Célula Responsáveis
  noAssignees: 'Sem responsável',
  // Aviso "Atribuir…" (§3.5, D-RTT-7) — botão dentro da célula Responsáveis,
  // condição `progress > 0 AND assignees = []`. Ícone + texto acessível, nunca só
  // o ícone. Não bloqueia nada.
  assignWarning: 'Atribuir…',
  assignWarningAria: (desc: string) => `Atribuir responsável para ${desc}`,
  openAssignAria: (desc: string) => `Editar responsáveis de ${desc}`,
  contributorTitle: 'Já registrou avanço, sem ser responsável',

  // Célula Trilha
  noTrail: 'Sem avanços',
  // Aviso "Registre o avanço…" (§3.5, D-RTT-6) — botão dentro da célula Trilha,
  // condição `0 < progress < 100 AND advances_count = 0`. A cláusula "nem nota"
  // (o campo legado `obs`) foi REMOVIDA: `advances_count` já conta a entrada
  // `legacy` que o importador cria da `obs`. Ver D-RTT-6.
  trailWarning: 'Registre o avanço…',
  trailWarningAria: (desc: string) => `Registrar o avanço de ${desc}`,
  trailCountAria: (n: number, desc: string) =>
    `Ver histórico de ${desc}: ${n} ${n === 1 ? 'entrada' : 'entradas'}`,

  // Modal de atribuição (mínimo na G3, enriquecido na G5)
  assignTitle: 'Responsáveis',
  assignResponsibles: 'Responsáveis atuais',
  assignContributors: 'Contribuíram (avançaram sem ser responsáveis)',
  assignEditComing: 'A edição de responsáveis chega no próximo passo.',

  // Modal de histórico (mínimo na G3, timeline completa na G5)
  historyTitle: 'Histórico da tarefa',
  historyEmpty: 'Nenhum avanço registrado ainda.',
  historyLegacy: 'importado',
  historyNoComment: 'sem comentário',
  historyFullComing: 'A trilha completa chega no próximo passo.',

  close: 'Fechar',
} as const
