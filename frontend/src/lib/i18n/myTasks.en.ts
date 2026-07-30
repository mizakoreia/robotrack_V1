import type { MyTasksText } from './myTasks'

// internationalization G4 — tradução EN de "Minhas Tarefas" → "My Tasks".
// "Visão Geral" → "Overview"; "Responsável" → "Assignee" (glossário do dono).
export const myTasksTextEn: MyTasksText = {
  title: 'My Tasks',

  colTask: 'Task',
  colStatus: 'Status',
  colProgress: 'Progress',
  colRobot: 'Robot',
  colCell: 'Cell',
  colProject: 'Project',
  openTaskAria: (desc: string, robot: string) => `Open ${desc} on robot ${robot}`,

  emptyTitle: 'No open tasks assigned to you',
  emptyBody: 'Completed tasks and those marked N/A do not appear here.',
  emptyAction: 'Go to Overview',

  identityTitle: 'Could not identify your record in this workspace.',
  identityBody: 'This is usually temporary. Try again in a moment.',
  retry: 'Try again',

  errorTitle: 'Could not load your tasks.',
  errorBody: 'Check your connection and try again.',

  loading: 'Loading…',
}
