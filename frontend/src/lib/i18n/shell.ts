import { defineText } from './defineText'
import { shellTextEn } from './shell.en'

// internationalization G3 — chrome do AppShell (nav, menu da conta, topbar, gaveta).
// Antes eram literais pt-BR inline; agora eixo de idioma sob `defineText`. O nome do
// produto ("RoboTrack") NÃO entra aqui — é marca, não texto traduzível.
//
// ATENÇÃO regra G do `convention-sweep`: `invitePerson` DEVE resolver ao MESMO valor
// pt-BR que `inviteText.inviteTitle` ('Convidar pessoa') — os dois controles têm o
// mesmo nome acessível de propósito e a colisão está na allowlist (o shell esconde o
// atalho na tela de Equipe). Mudar este valor quebraria a allowlist.
const shellTextPtBR = {
  // gaveta (dialog) e navegação
  drawerNav: 'Navegação',
  navAria: 'Navegação principal',
  nav: {
    overview: 'Visão Geral',
    myTasks: 'Minhas Tarefas',
    report: 'Relatório',
  },
  // menu da conta (rodapé da sidebar)
  account: {
    menuLabel: 'Conta',
    aria: (name: string) => `Conta: ${name}`,
    settings: 'Configurações do workspace',
    team: 'Equipe e convites',
    toggleTheme: 'Alternar tema',
    logout: 'Sair',
  },
  // topbar
  openMenu: 'Abrir menu',
  help: 'Ajuda',
  invitePerson: 'Convidar pessoa',
}

export type ShellText = typeof shellTextPtBR
export const shellText: ShellText = defineText(shellTextPtBR, shellTextEn)
