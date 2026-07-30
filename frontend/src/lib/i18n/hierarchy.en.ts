import type { HierarchyText } from './hierarchy'

// internationalization G4 — tradução EN dos textos das telas de hierarquia.
// Glossário confirmado: "Visão Geral" → Overview; "progresso físico global" →
// "overall task completion"; "progresso físico" → "task completion".
export const hierarchyTextEn: HierarchyText = {
  overview: {
    hub: {
      activeProjects: 'Active projects',
      analyzedRobots: 'Robots analysed',
      completedTasks: 'Completed tasks',
      physicalCaption: (percent: number) => `${percent}% overall task completion`,
    },
    cardFooterMacro: 'Macro view',
    cardFooterOpen: 'Open',
    empty: {
      title: 'No projects yet',
      body: 'Create the first project to start tracking commissioning.',
      bodyView: 'No project has been created in this workspace yet.',
      cta: 'New project',
    },
    error: {
      body: 'Could not load the Overview.',
      retry: 'Try again',
    },
    remove: {
      title: 'Delete project',
      body: (name: string) =>
        `Delete the project "${name}"? Its cells, robots and tasks are also archived. This action cannot be undone.`,
    },
  },
  project: {
    back: 'Back to Overview',
    newCell: 'New cell',
    cellFooter: 'Overall status',
    hub: { configuredCells: 'Configured cells', analyzedRobots: 'Robots analysed', completedTasks: 'Completed tasks' },
    empty: {
      title: 'No cells yet',
      body: 'Create the first cell of this project to start organising the robots.',
      bodyView: 'This project has no cells yet.',
      cta: 'New cell',
    },
    rename: { title: 'Rename cell' },
    remove: {
      title: 'Delete cell',
      body: (name: string) =>
        `Delete the cell "${name}"? Its robots and tasks are also archived. This action cannot be undone.`,
    },
  },
  cell: {
    back: 'Back to project',
    addRobots: 'Add robots',
    robotOpen: 'Open',
    hub: { configuredRobots: 'Configured robots', completedTasks: 'Completed tasks' },
    empty: {
      title: 'No robots yet',
      body: 'Add robots to this cell to materialise the commissioning tasks.',
      bodyView: 'This cell has no robots yet.',
      cta: 'Add robots',
    },
    remove: {
      title: 'Delete robot',
      body: (name: string) =>
        `Delete the robot "${name}"? Its tasks are also archived. This action cannot be undone.`,
    },
  },
  levelPhysicalCaption: (percent: number) => `${percent}% task completion`,
  cellsBadge: (n: number) => `${n} ${n === 1 ? 'cell' : 'cells'}`,
  robotsBadge: (n: number) => `${n} ${n === 1 ? 'robot' : 'robots'}`,
  tasksFooter: (n: number) => `${n} ${n === 1 ? 'task' : 'tasks'}`,
}
