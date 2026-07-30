import type { ShellText } from './shell'

// internationalization G3 — EN do chrome do AppShell. Glossário confirmado:
// Overview / My Tasks / Report; Account; Settings; Sign out; Help; Invite person.
export const shellTextEn: ShellText = {
  drawerNav: 'Navigation',
  navAria: 'Main navigation',
  nav: {
    overview: 'Overview',
    myTasks: 'My Tasks',
    report: 'Report',
  },
  account: {
    menuLabel: 'Account',
    aria: (name: string) => `Account: ${name}`,
    settings: 'Workspace settings',
    team: 'Team and invitations',
    toggleTheme: 'Toggle theme',
    logout: 'Sign out',
  },
  openMenu: 'Open menu',
  help: 'Help',
  invitePerson: 'Invite person',
}
