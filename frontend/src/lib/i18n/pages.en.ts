import type { PagesText } from './pages'

// internationalization G3 — tradução EN (UK) dos textos inline das telas centrais.
// Glossário confirmado pelo dono: "Resumo do workspace" → "Workspace summary";
// "Nome do projeto" → "Project name"; "Nome da célula" → "Cell name"; "Filtro de
// tarefas" → "Task filter"; "Carregando" → "Loading"; "Dispensar aviso" → "Dismiss
// warning"; "Gráfico de pizza/barras/linha" → "Pie/Bar/Line chart".
export const pagesTextEn: PagesText = {
  common: {
    cancel: 'Cancel',
    create: 'Create',
    save: 'Save',
    delete: 'Delete',
    retry: 'Try again',
    loading: 'Loading',
    ringsLegend: 'Rings: weighted progress by task weight',
    deleteAria: (name: string) => `Delete ${name}`,
    renameAria: (name: string) => `Rename ${name}`,
  },
  overview: {
    title: 'Overview',
    summaryLabel: 'Workspace summary',
    projectNamePlaceholder: 'Project name',
  },
  project: {
    cellNamePlaceholder: 'Cell name',
  },
  robotTask: {
    backToCell: 'Back to cell',
    robotFallback: 'Robot',
    filterLabel: 'Task filter',
    filterAll: 'All',
    filterPending: 'Pending',
    filterDone: 'Done',
    select: 'Select',
    colTask: 'Task',
    colStatus: 'Status',
    colProgress: 'Progress',
    colAssignees: 'Assignees',
    colTrail: 'Trail',
    colActions: 'Actions',
    emptyTitle: (robot: string) => `No tasks in ${robot}`,
    emptyBody: 'Add tasks or sync the base tasks to start commissioning this robot.',
    errorBody: 'Could not load the robot tasks.',
  },
  storage: {
    baseMessage:
      'Your browser is blocking storage. You can use RoboTrack normally, but the session will not persist when you close it',
    memorySuffix: ', and changes made offline will not be saved',
    dismiss: 'Dismiss',
    dismissAria: 'Dismiss warning',
  },
  charts: {
    pie: 'Pie chart',
    bar: 'Bar chart',
    line: 'Line chart',
  },
}
