import type { IconName } from '@/components/icons/sprite'

// app-shell-navigation 4.2 (§DESIGN Navegação, D-F) — a sidebar tem EXATAMENTE
// três destinos. Constante FECHADA: nenhum item de configuração entra aqui (mora
// no rodapé). `matches` mantém "Visão Geral" ativo em toda a subárvore da
// hierarquia (`/projeto/8f2a/celula/1c9b`), não só na raiz exata.
export interface NavDestination {
  to: string
  label: string
  icon: IconName
  matches: (pathname: string) => boolean
}

export const NAV_DESTINATIONS: readonly NavDestination[] = [
  {
    to: '/',
    label: 'Visão Geral',
    icon: 'home',
    matches: (p) => p === '/' || p.startsWith('/projeto') || p.startsWith('/celula') || p.startsWith('/robo'),
  },
  {
    to: '/minhas-tarefas',
    label: 'Minhas Tarefas',
    icon: 'list',
    matches: (p) => p.startsWith('/minhas-tarefas'),
  },
  {
    to: '/relatorio',
    label: 'Relatório',
    icon: 'file',
    matches: (p) => p.startsWith('/relatorio'),
  },
] as const
