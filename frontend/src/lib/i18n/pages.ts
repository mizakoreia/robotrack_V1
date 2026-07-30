import { defineText } from './defineText'
import { pagesTextEn } from './pages.en'

// internationalization G3 — módulo ÚNICO dos textos INLINE que sobravam nas telas
// centrais (Visão Geral / Projeto / Célula / tabela do robô / aviso de storage /
// gráficos): aria-labels, placeholders, cabeçalhos de coluna e alguns rótulos
// visíveis que ainda eram literais soltos. Os textos de contexto/estado dessas
// telas já vivem em `hierarchy.ts` / `robotTasks.ts` / `myTasks.ts`; aqui ficam só
// os que faltavam. Agrupado por tela para leitura.
//
// NÃO ENTRAM AQUI os VALORES DE DADOS que a UI só mapeia para exibição — status
// 'Pendente'/'Em Andamento'/'Concluído'/'N/A', nome da aplicação do robô,
// descrição de tarefa-base — esses permanecem pt-BR e são mapeados noutro lugar.
//
// internationalization D-I2 — `pagesText` é o eixo de idioma (pt-BR + en) sob o
// MESMO nome; o pt-BR canônico vive neste objeto (os sweeps o leem), o en em
// `pages.en.ts`. O idioma é resolvido no runtime.
const pagesTextPtBR = {
  // Chrome genérico reusado em várias telas (ações de diálogo, aria de card).
  common: {
    cancel: 'Cancelar',
    create: 'Criar',
    save: 'Salvar',
    delete: 'Excluir',
    retry: 'Tentar novamente',
    loading: 'Carregando',
    // legenda única da grade de cards (D-B) — a MESMA nas três telas de nível.
    ringsLegend: 'Anéis: progresso ponderado por peso de tarefa',
    deleteAria: (name: string) => `Excluir ${name}`,
    renameAria: (name: string) => `Renomear ${name}`,
  },
  overview: {
    title: 'Visão Geral',
    summaryLabel: 'Resumo do workspace',
    projectNamePlaceholder: 'Nome do projeto',
  },
  project: {
    cellNamePlaceholder: 'Nome da célula',
  },
  robotTask: {
    backToCell: 'Voltar à célula',
    robotFallback: 'Robô',
    filterLabel: 'Filtro de tarefas',
    // rótulos das abas do filtro (chrome), NÃO os valores de status do banco.
    filterAll: 'Todos',
    filterPending: 'Pendentes',
    filterDone: 'Concluídos',
    select: 'Selecionar',
    // cabeçalhos de coluna (reusados como rótulos das linhas do cartão mobile).
    colTask: 'Tarefa',
    colStatus: 'Status',
    colProgress: 'Progresso',
    colAssignees: 'Responsáveis',
    colTrail: 'Trilha',
    colActions: 'Ações',
    emptyTitle: (robot: string) => `Nenhuma tarefa em ${robot}`,
    emptyBody: 'Adicione tarefas ou sincronize as tarefas-base para começar o comissionamento deste robô.',
    errorBody: 'Não foi possível carregar as tarefas do robô.',
  },
  // Aviso de armazenamento bloqueado (offline-pwa 1.3 / D7-11). As DUAS redações
  // são LEI do D7-11: base + (em memory-only) o sufixo. A composição continua no
  // componente; aqui ficam as partes.
  storage: {
    baseMessage:
      'Seu navegador está bloqueando o armazenamento. Você pode usar o RoboTrack normalmente, mas a sessão não vai persistir ao fechar',
    memorySuffix: ', e alterações feitas sem conexão não serão salvas',
    dismiss: 'Dispensar',
    dismissAria: 'Dispensar aviso',
  },
  charts: {
    pie: 'Gráfico de pizza',
    bar: 'Gráfico de barras',
    line: 'Gráfico de linhas',
  },
}

// internationalization D-I2 — SEM `as const`: o tipo alarga os literais para `string`
// e `en` pode ter outro texto. Os sweeps leem o TEXTO do arquivo, não o tipo — o
// canônico pt-BR segue estático e verificável. O idioma é resolvido no runtime.
export type PagesText = typeof pagesTextPtBR
export const pagesText: PagesText = defineText(pagesTextPtBR, pagesTextEn)
