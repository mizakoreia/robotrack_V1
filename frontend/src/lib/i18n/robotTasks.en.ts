import type { RobotTaskText } from './robotTasks'

// internationalization G4 — tradução EN dos textos da tabela de tarefas do robô.
// Glossário confirmado: "Responsável/Responsáveis" → "Assignee/Assignees";
// "Sem avanços" → "No progress updates"; "Registre o avanço" → "Log progress";
// "Já registrou avanço, sem ser responsável" → "Already logged progress, without
// being an assignee"; "Sincronizar tarefas-base" → "Sync base tasks". Sem valores
// de banco neste módulo — todas as strings são chrome (rótulos, aria, avisos).
export const robotTaskTextEn: RobotTaskText = {
  // Assignees cell
  noAssignees: 'No assignee',
  assignWarning: 'Assign…',
  assignWarningAria: (desc: string) => `Assign an assignee to ${desc}`,
  openAssignAria: (desc: string) => `Edit assignees of ${desc}`,
  contributorTitle: 'Already logged progress, without being an assignee',

  // Trail cell
  noTrail: 'No progress updates',
  trailWarning: 'Log progress…',
  trailWarningAria: (desc: string) => `Log progress for ${desc}`,
  trailCountAria: (n: number, desc: string) =>
    `View history of ${desc}: ${n} ${n === 1 ? 'entry' : 'entries'}`,

  // Assignment modal (5.3/5.4)
  assignTitle: 'Assignees',
  assignPeople: 'Workspace people',
  assignEmpty: 'No people registered yet.',
  assignAddLabel: 'Register a new person',
  assignAddPlaceholder: "Person's name",
  assignAddButton: 'Add',
  assignSave: 'Save assignees',
  assignSaving: 'Saving…',
  assignDuplicate: (name: string) => `${name} already exists — selected.`,
  assignBlank: 'Enter a name.',
  assignLoadError: 'Could not load the people.',

  // History modal (full timeline, 5.1/5.2)
  historyTitle: 'Task history',
  historyEmpty: 'No progress updates logged yet.',
  historyLegacy: 'imported',
  historyNoComment: 'no comment',
  historyFromTo: (from: number, to: number) => `${from}% → ${to}%`,
  historyLoadError: 'Could not load the history.',
  historyLoading: 'Loading…',

  // Actions column (4.3) + header (4.2)
  editAction: 'Edit',
  editAria: (desc: string) => `Edit the description of ${desc}`,
  deleteAction: 'Delete',
  deleteAria: (desc: string) => `Delete ${desc}`,
  editTitle: 'Edit task',
  editField: 'Description',
  save: 'Save',
  deleteTitle: 'Delete task',
  deleteConfirm: (desc: string) => `Delete “${desc}”? This action cannot be undone.`,
  // robot-task-grouping G3 — multi-select / bulk delete
  selectAria: (desc: string) => `Select ${desc}`,
  selectedCount: (n: number) => `${n} ${n === 1 ? 'task selected' : 'tasks selected'}`,
  bulkDelete: 'Delete selected',
  clearSelection: 'Clear selection',
  bulkDeleteTitle: 'Delete tasks',
  bulkDeleteConfirm: (n: number) =>
    `Delete ${n} ${n === 1 ? 'task' : 'tasks'}? This action cannot be undone. Progress is recalculated.`,
  addTask: 'Add task',
  addTitle: 'New task',
  addCategory: 'Category',
  addDescription: 'Description',
  add: 'Add',
  syncTemplates: 'Sync base tasks',
  syncing: 'Syncing…',
  syncResult: (n: number) => `${n} ${n === 1 ? 'task added' : 'tasks added'}`,
  syncNone: 'No new tasks to add',
  cancel: 'Cancel',

  close: 'Close',
}
