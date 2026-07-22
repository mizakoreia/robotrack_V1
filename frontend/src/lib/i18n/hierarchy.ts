// hierarchy-screens (D14/D-B) — módulo ÚNICO das strings das telas de hierarquia.
// Nenhum literal de rótulo vive numa tela; o hub, os estados vazios e os rodapés
// leem daqui. Os rótulos das DUAS métricas de progresso continuam em
// `lib/i18n/progress.ts` (fonte deles); aqui ficam só os textos de contexto (ex.:
// "de progresso físico global") e as ações.
export const hierarchyText = {
  overview: {
    hub: {
      activeProjects: 'Projetos ativos',
      analyzedRobots: 'Robôs analisados',
      completedTasks: 'Tarefas concluídas',
      // §3.2 / D-B — o rótulo contextual do percentual do hub da Visão Geral.
      physicalCaption: (percent: number) => `${percent}% de progresso físico global`,
    },
    cardFooterMacro: 'Visão macro',
    cardFooterOpen: 'Acessar',
    empty: {
      title: 'Nenhum projeto ainda',
      body: 'Crie o primeiro projeto para começar a acompanhar o comissionamento.',
      bodyView: 'Nenhum projeto foi criado neste workspace ainda.',
      cta: 'Novo Projeto',
    },
    error: {
      body: 'Não foi possível carregar a Visão Geral.',
      retry: 'Tentar novamente',
    },
  },
  // §3.3 / §3.4 — rótulo de progresso físico dos níveis internos.
  levelPhysicalCaption: (percent: number) => `${percent}% de progresso físico`,
  // badges de contagem, com plural pt-BR.
  cellsBadge: (n: number) => `${n} ${n === 1 ? 'célula' : 'células'}`,
  robotsBadge: (n: number) => `${n} ${n === 1 ? 'robô' : 'robôs'}`,
  tasksFooter: (n: number) => `${n} ${n === 1 ? 'tarefa' : 'tarefas'}`,
} as const
