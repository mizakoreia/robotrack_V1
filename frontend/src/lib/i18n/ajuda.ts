import { defineText } from './defineText'
import { ajudaTextEn } from './ajuda.en'

// ajuda-screen (D14/D-I2) — módulo ÚNICO da prosa da tela de Ajuda (rota `/ajuda`).
// A prosa longa da Ajuda mora AQUI, estruturada por dados: a MESMA lista de seções
// alimenta o índice navegável (TOC) e o corpo, então os dois nunca divergem — em
// pt-BR ou en. O `AjudaPage.tsx` só mapeia esta estrutura para JSX.
//
// Modelo de texto rico (para manter a prosa traduzível, com termos em destaque no
// meio da frase, sem estourar em dezenas de chaves):
//   - `AjudaRun`  — um trecho: string simples, `{ b }` (termo em negrito) ou
//     `{ ref }` (rótulo vindo de OUTRO módulo i18n — as duas métricas de progresso
//     e o item de menu de convite — que se resolve no idioma corrente na tela).
//   - `AjudaBlock` — um parágrafo (`p`), uma lista de passos (`steps`) ou a tabela
//     de papéis (`rolesTable`, só na seção de papéis).
//
// Os ids das seções são ÂNCORAS estruturais (`#o-que-e` etc.) — NÃO se traduzem,
// senão os links da página quebram. Só a prosa muda de idioma.
//
// internationalization D-I2 — `ajudaText` é o eixo de idioma (pt-BR + en) sob o
// MESMO nome; o pt-BR canônico vive neste objeto (os sweeps o leem), o en em
// `ajuda.en.ts`. O idioma é resolvido no runtime pelo `defineText`.

export type AjudaRun = string | { b: string } | { ref: 'weighted' | 'raw_count' | 'joinByCode' }
export type AjudaBlock = { p: AjudaRun[] } | { steps: AjudaRun[][] } | { rolesTable: true }
export interface AjudaSection {
  id: string
  title: string
  body: AjudaBlock[]
}

export interface AjudaTextShape {
  pageTitle: string
  pageIntro: string
  navLabel: string
  roles: {
    caption: string
    actionHeader: string
    yes: string
    no: string
    badges: { owner: string; editor: string; viewer: string }
    // rótulos das ações; o padrão de permissão (dono/editor/viewer) é estrutural e
    // vive na tela, casado por índice com esta lista.
    actions: string[]
  }
  sections: AjudaSection[]
}

const ajudaTextPtBR: AjudaTextShape = {
  pageTitle: 'Ajuda',
  pageIntro: 'Como o RoboTrack funciona e como usar, do começo ao fim. Toque em uma seção para ir direto a ela.',
  navLabel: 'Seções da ajuda',
  roles: {
    caption: 'O que cada papel pode fazer',
    actionHeader: 'Ação',
    yes: 'Sim',
    no: 'não',
    badges: { owner: 'Dono', editor: 'Editor', viewer: 'Visualizador' },
    actions: [
      'Ver tudo',
      'Registrar avanço',
      'Criar e editar projetos, células, robôs e tarefas',
      'Atribuir responsáveis',
      'Convidar pessoas',
      'Excluir cards e resetar o workspace',
    ],
  },
  sections: [
    {
      id: 'o-que-e',
      title: 'O que é o RoboTrack',
      body: [
        {
          p: [
            'O RoboTrack acompanha o ',
            { b: 'comissionamento de robôs industriais' },
            ' — do primeiro parafuso ao protocolo assinado. Cada tarefa de cada robô recebe um avanço registrado, e esse avanço sobe pela hierarquia até virar o quadro geral do projeto.',
          ],
        },
        {
          p: [
            'Ele foi feito para o chão de fábrica: legível de longe, com alvos de toque grandes (dá para usar de luva) e funcionando mesmo ',
            { b: 'sem internet' },
            '. A ferramenta serve ao trabalho — registrar o avanço leva segundos e o número que se assina no fim é confiável.',
          ],
        },
      ],
    },
    {
      id: 'estrutura',
      title: 'Como o trabalho se organiza',
      body: [
        { p: ['O trabalho é organizado em cinco níveis, do maior para o menor:'] },
        {
          steps: [
            [
              { b: 'Workspace' },
              ' — o espaço da sua empresa/equipe. Cada pessoa é dona do próprio e pode ser convidada para colaborar em outros.',
            ],
            [{ b: 'Projeto' }, ' — uma entrega de comissionamento.'],
            [{ b: 'Célula' }, ' — um agrupamento de robôs dentro do projeto (por linha, estação etc.).'],
            [{ b: 'Robô' }, ' — o equipamento a ser comissionado. É aqui que você trabalha no dia a dia.'],
            [{ b: 'Tarefa' }, ' — cada item a concluir num robô (montagem, teste, ajuste…).'],
          ],
        },
        {
          p: [
            'O progresso ',
            { b: 'consolida de baixo para cima' },
            ': você registra o avanço na tarefa, e o robô, a célula e o projeto se recalculam sozinhos. Você nunca preenche o número do projeto na mão.',
          ],
        },
        {
          p: [
            'Para não confundir, o RoboTrack sempre mostra ',
            { b: 'duas medidas com nome' },
            ', nunca um “progresso” solto:',
          ],
        },
        {
          steps: [
            [
              { ref: 'weighted' },
              ' — a média do avanço das tarefas por peso (é o anel de progresso). Mostra o quanto do trabalho, de fato, já foi feito.',
            ],
            [
              { ref: 'raw_count' },
              ' — quantas tarefas foram concluídas dividido pelo total. Mostra quantos itens já fecharam, sem peso.',
            ],
          ],
        },
      ],
    },
    {
      id: 'papeis',
      title: 'Papéis e permissões',
      body: [
        { p: ['Cada pessoa num workspace tem um papel, e o papel decide o que ela pode fazer:'] },
        { rolesTable: true },
        {
          p: [
            'Quem autoriza é sempre o servidor: a tela apenas esconde o que você não pode fazer. Se um botão não aparece para você, é porque o seu papel não permite aquela ação.',
          ],
        },
      ],
    },
    {
      id: 'navegar',
      title: 'Navegando pelo app',
      body: [
        {
          p: [
            'A barra lateral tem três destinos fixos. O resto (Configurações, Ajuda, conta) mora no menu da conta, no canto inferior esquerdo, e nesta barra do topo.',
          ],
        },
        {
          steps: [
            [
              { b: 'Visão Geral' },
              ' — seus projetos, cada um com as duas medidas de progresso. É a porta de entrada.',
            ],
            [{ b: 'Projeto → Célula' }, ' — desça a hierarquia tocando nos cards para chegar aos robôs.'],
            [
              { b: 'Tela do robô' },
              ' — a tabela de tarefas, onde o trabalho acontece. As tarefas ficam em grupos que abrem e fecham, com colunas de status, progresso, responsáveis e histórico.',
            ],
            [{ b: 'Minhas Tarefas' }, ' — só as tarefas atribuídas a você, reunidas de todos os robôs.'],
            [{ b: 'Relatório' }, ' — o Protocolo de Comissionamento, pronto para imprimir.'],
            [
              { b: 'Configurações' },
              ' — pessoas responsáveis, tarefas-base, aparência, equipe/convites e (para o dono) backup e reset.',
            ],
          ],
        },
      ],
    },
    {
      id: 'montar',
      title: 'Montando a estrutura',
      body: [
        {
          p: [
            'O dono ou um editor monta a hierarquia de cima para baixo. Em cada tela há o botão para adicionar o nível de baixo:',
          ],
        },
        {
          steps: [
            ['Na Visão Geral, use ', { b: 'Novo Projeto' }, '.'],
            ['Dentro do projeto, use ', { b: 'Nova célula' }, '.'],
            ['Dentro da célula, use ', { b: 'Adicionar robôs' }, '.'],
          ],
        },
        {
          p: [
            'Ao adicionar robôs, um assistente de dois passos permite criar ',
            { b: 'vários de uma vez' },
            ' — de 1 a 50 — informando a quantidade e a aplicação. Cada robô já nasce com as tarefas-base do catálogo que valem para aquela aplicação.',
          ],
        },
        {
          p: [
            'Na tela do robô, o editor pode ',
            { b: 'Adicionar tarefa' },
            ' avulsa, editar as existentes e usar ',
            { b: 'Sincronizar tarefas-base' },
            ' para trazer as tarefas do catálogo que ainda faltam naquele robô. O catálogo em si é gerenciado em Configurações → Tarefas-base.',
          ],
        },
      ],
    },
    {
      id: 'avanco',
      title: 'Registrando o avanço de uma tarefa',
      body: [
        { p: ['É a ação mais comum no dia a dia, e leva segundos:'] },
        {
          steps: [
            ['Na tela do robô, mexa no controle de progresso da tarefa.'],
            [
              'Arraste até a porcentagem real. Ao ',
              { b: 'soltar' },
              ', abre a janela ',
              { b: 'Registrar avanço' },
              '.',
            ],
            [
              'Abaixo de 100%, o ',
              { b: 'comentário é obrigatório' },
              ' (diga o que foi feito ou o que falta). Ao chegar a 100%, o comentário é opcional.',
            ],
            [
              'Toque em ',
              { b: 'Registrar' },
              '. O avanço entra no histórico da tarefa — que não pode ser apagado — e o progresso do robô, da célula e do projeto se recalcula na hora.',
            ],
          ],
        },
        {
          p: [
            'O status acompanha o número: ',
            { b: 'Pendente' },
            ' em 0%, ',
            { b: 'Em Andamento' },
            ' entre 1% e 99% e ',
            { b: 'Concluída' },
            ' em 100%. Trocar o status também passa pela mesma janela de avanço.',
          ],
        },
        {
          p: [
            'O RoboTrack é honesto sobre o que salvou: só diz “salvo” quando salvou de verdade. Sem internet, o avanço fica pendente na fila e sincroniza quando a rede voltar (veja “Usando sem internet”).',
          ],
        },
      ],
    },
    {
      id: 'responsaveis',
      title: 'Atribuindo responsáveis',
      body: [
        {
          p: [
            'Na tela do robô, a coluna ',
            { b: 'Responsáveis' },
            ' define quem cuida de cada tarefa. A atribuição é ',
            { b: 'por pessoa' },
            ': marque as pessoas na lista — e, se ela ainda não existe, cadastre-a ali mesmo. Uma tarefa pode ter mais de um responsável.',
          ],
        },
        {
          p: [
            'Quem é responsável recebe notificação dos avanços daquela tarefa e a vê em ',
            { b: 'Minhas Tarefas' },
            '. As pessoas também podem ser cadastradas e organizadas em Configurações → Responsáveis.',
          ],
        },
      ],
    },
    {
      id: 'convites',
      title: 'Convidando pessoas',
      body: [
        {
          p: [
            'Convites funcionam por ',
            { b: 'código' },
            '. Quem gerencia (dono ou editor) usa ',
            { b: 'Convidar pessoa' },
            ' na barra do topo, escolhe o papel (Editor ou Visualizador) e recebe um código curto, no formato ',
            { b: 'XXXX-XXXX' },
            '. Basta passar esse código para a pessoa.',
          ],
        },
        { p: ['Quem recebeu o código entra de duas formas:'] },
        {
          steps: [
            ['Ainda sem conta ou deslogada: na tela de entrada, em ', { b: '“Tenho um código de convite”' }, '.'],
            [
              'Já logada em outro workspace: no menu da conta, na opção ',
              { ref: 'joinByCode' },
              '. O app troca para o novo workspace e abre a Visão Geral dele.',
            ],
          ],
        },
      ],
    },
    {
      id: 'notificacoes',
      title: 'Notificações',
      body: [
        {
          p: [
            'O ',
            { b: 'sino' },
            ' na barra do topo mostra quantas notificações você tem por ler; tocá-lo abre a central. Por padrão, você recebe avisos das tarefas em que é responsável.',
          ],
        },
        {
          p: [
            'Além disso, no cabeçalho de cada projeto, célula e robô há um sino de ',
            { b: 'preferência' },
            ', com três opções:',
          ],
        },
        {
          steps: [
            [{ b: 'Seguir' }, ' — receber os avanços daquele nível mesmo sem ser responsável.'],
            [{ b: 'Silenciar' }, ' — não receber daquele nível.'],
            [{ b: 'Padrão' }, ' — o comportamento normal (você recebe do que é responsável).'],
          ],
        },
        {
          p: [
            'Vale a regra do ',
            { b: 'mais específico vence' },
            ': se você silencia uma célula, cala os robôs dela — mas se seguir um robô específico dentro dela, volta a receber daquele robô. O sino sempre mostra o estado que está valendo e de onde ele vem.',
          ],
        },
        {
          p: [
            'O dono recebe os avanços de todo o workspace dele, para acompanhar sem depender de estar atribuído.',
          ],
        },
      ],
    },
    {
      id: 'offline',
      title: 'Usando sem internet',
      body: [
        {
          p: [
            'O RoboTrack é um app que funciona ',
            { b: 'offline' },
            '. Depois de abrir online pelo menos uma vez, ele continua funcionando sem rede:',
          ],
        },
        {
          steps: [
            ['As leituras vêm do que já foi carregado (o que você viu enquanto estava online).'],
            [
              'As escritas — avanços, edições — entram numa ',
              { b: 'fila' },
              ' e sincronizam sozinhas quando a rede volta.',
            ],
            ['O app avisa quando está offline e quando há itens pendentes: você nunca acha que salvou sem salvar.'],
          ],
        },
        {
          p: [
            'A única exceção: ',
            { b: 'entrar e criar conta precisam de internet' },
            '. Uma vez dentro, o galpão sem sinal deixa de ser problema.',
          ],
        },
      ],
    },
    {
      id: 'excluir',
      title: 'Excluindo itens',
      body: [
        {
          p: ['Só o ', { b: 'Dono' }, ' exclui projetos, células, robôs e tarefas. As formas de excluir:'],
        },
        {
          steps: [
            ['No computador: pelo ícone de ', { b: 'lixeira' }, ' no card ou na linha.'],
            ['No celular: ', { b: 'arraste o card para a esquerda' }, ' para revelar o botão Excluir.'],
          ],
        },
        {
          p: [
            'Excluir sempre pede ',
            { b: 'confirmação' },
            ' — nada some com um toque. Ao excluir um item, o que está abaixo dele também é arquivado (excluir um projeto arquiva suas células, robôs e tarefas). O histórico e a auditoria são preservados.',
          ],
        },
      ],
    },
    {
      id: 'relatorio',
      title: 'Relatório de comissionamento',
      body: [
        {
          p: [
            'Em ',
            { b: 'Relatório' },
            ', o RoboTrack monta o ',
            { b: 'Protocolo de Comissionamento' },
            ' — o documento formal que se assina no fim do trabalho. Ele consolida o progresso real de projetos, células e robôs.',
          ],
        },
        {
          p: [
            'O documento é em formato ',
            { b: 'A4' },
            ', pronto para imprimir (ou salvar em PDF pela opção de impressão do navegador).',
          ],
        },
      ],
    },
  ],
}

// internationalization D-I2 — SEM `as const`: o tipo alarga os literais para `string`
// e `en` pode ter outro texto. Os sweeps leem o TEXTO do arquivo, não o tipo — o
// canônico pt-BR segue estático e verificável. O idioma é resolvido no runtime.
export type AjudaText = typeof ajudaTextPtBR
export const ajudaText: AjudaText = defineText(ajudaTextPtBR, ajudaTextEn)
