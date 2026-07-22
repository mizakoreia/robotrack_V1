// Módulo ÚNICO dos textos de "Minhas Tarefas" (my-tasks-view, D14). Os TRÊS
// estados de D-MTV-8 têm strings distintas de propósito: colapsar o "409
// identidade ausente" no estado vazio reintroduziria no cliente a falha silenciosa
// que a capacidade inteira existe para matar (uma lista vazia enganosa).
export const myTasksText = {
  title: 'Minhas Tarefas',

  // Colunas
  colTask: 'Tarefa',
  colStatus: 'Status',
  colProgress: 'Progresso',
  colRobot: 'Robô',
  colCell: 'Célula',
  colProject: 'Projeto',
  openTaskAria: (desc: string, robot: string) => `Abrir ${desc} no robô ${robot}`,

  // Estado 1 — vazio LEGÍTIMO (200 []). A segunda linha existe porque o modo de
  // confusão real é concluir a última tarefa, a linha sumir, e achar que perdeu dado.
  emptyTitle: 'Nenhuma tarefa aberta atribuída a você',
  emptyBody: 'Tarefas concluídas e marcadas como N/A não aparecem aqui.',
  emptyAction: 'Ir para Visão Geral',

  // Estado 2 — identidade ausente (409 person_missing). NUNCA se parece com o vazio.
  identityTitle: 'Não foi possível identificar seu cadastro neste workspace.',
  identityBody: 'Isso costuma ser temporário. Tente novamente em instantes.',
  retry: 'Tentar novamente',

  // Estado 3 — falha de rede/servidor.
  errorTitle: 'Não foi possível carregar suas tarefas.',
  errorBody: 'Verifique a conexão e tente novamente.',

  loading: 'Carregando…',
} as const
