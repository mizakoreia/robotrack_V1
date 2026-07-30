import { Badge } from '@/components/ui/Badge'
import { progressText } from '@/lib/i18n/progress'
import { inviteText } from '@/lib/i18n/invitations'

// ajuda-screen — a tela de Ajuda (rota `/ajuda`), alcançável pelo "?" da topbar.
// Frontend puro, sem banco: descreve o app REAL no estado atual. O conteúdo é
// prosa longa para dois públicos (operador de chão de fábrica + dono/gestor) e,
// como toda prosa de ajuda, mora AQUI (não em `lib/i18n/*`, que guarda o chrome
// reusável das telas — D14). Estrutura dirigida por dados: a mesma lista alimenta
// o índice navegável e as seções, então TOC e conteúdo nunca divergem.
//
// Legibilidade sob luz de galpão (PRODUCT §Design): corpo em `text-text-main`
// (nunca cinza-claro por elegância), medida de leitura contida (~68ch), degraus
// de tipografia nomeados (`.title`/`.panel-header`/`.label-md`). Sem card por
// enfeite (Princípio 5) — o ritmo vem do espaçamento e das réguas, não de caixas.

interface Section {
  id: string
  title: string
  body: React.ReactNode
}

// Bloco de prosa com medida de leitura contida e ritmo entre parágrafos.
function P({ children }: { children: React.ReactNode }) {
  return <p className="max-w-[68ch] leading-relaxed text-text-main">{children}</p>
}

// Termo em destaque dentro da prosa (peso, não cor — evita ruído de cor semântica).
function Term({ children }: { children: React.ReactNode }) {
  return <strong className="font-semibold text-text-main">{children}</strong>
}

// Lista de passos/itens; marcadores discretos, texto no corpo legível.
function Steps({ items }: { items: React.ReactNode[] }) {
  return (
    <ul className="max-w-[68ch] space-y-1.5 text-text-main">
      {items.map((it, i) => (
        <li key={i} className="flex gap-2 leading-relaxed">
          <span aria-hidden="true" className="mt-[0.55em] h-1.5 w-1.5 shrink-0 rounded-full bg-accent" />
          <span>{it}</span>
        </li>
      ))}
    </ul>
  )
}

const SECTIONS: Section[] = [
  {
    id: 'o-que-e',
    title: 'O que é o RoboTrack',
    body: (
      <>
        <P>
          O RoboTrack acompanha o <Term>comissionamento de robôs industriais</Term> — do primeiro parafuso ao
          protocolo assinado. Cada tarefa de cada robô recebe um avanço registrado, e esse avanço sobe pela
          hierarquia até virar o quadro geral do projeto.
        </P>
        <P>
          Ele foi feito para o chão de fábrica: legível de longe, com alvos de toque grandes (dá para usar de
          luva) e funcionando mesmo <Term>sem internet</Term>. A ferramenta serve ao trabalho — registrar o avanço
          leva segundos e o número que se assina no fim é confiável.
        </P>
      </>
    ),
  },
  {
    id: 'estrutura',
    title: 'Como o trabalho se organiza',
    body: (
      <>
        <P>O trabalho é organizado em cinco níveis, do maior para o menor:</P>
        <Steps
          items={[
            <>
              <Term>Workspace</Term> — o espaço da sua empresa/equipe. Cada pessoa é dona do próprio e pode ser
              convidada para colaborar em outros.
            </>,
            <>
              <Term>Projeto</Term> — uma entrega de comissionamento.
            </>,
            <>
              <Term>Célula</Term> — um agrupamento de robôs dentro do projeto (por linha, estação etc.).
            </>,
            <>
              <Term>Robô</Term> — o equipamento a ser comissionado. É aqui que você trabalha no dia a dia.
            </>,
            <>
              <Term>Tarefa</Term> — cada item a concluir num robô (montagem, teste, ajuste…).
            </>,
          ]}
        />
        <P>
          O progresso <Term>consolida de baixo para cima</Term>: você registra o avanço na tarefa, e o robô, a
          célula e o projeto se recalculam sozinhos. Você nunca preenche o número do projeto na mão.
        </P>
        <P>
          Para não confundir, o RoboTrack sempre mostra <Term>duas medidas com nome</Term>, nunca um “progresso”
          solto:
        </P>
        <Steps
          items={[
            <>
              <Term>{progressText.metrics.weighted.label}</Term> — a média do avanço das tarefas por peso (é o anel
              de progresso). Mostra o quanto do trabalho, de fato, já foi feito.
            </>,
            <>
              <Term>{progressText.metrics.raw_count.label}</Term> — quantas tarefas foram concluídas dividido pelo
              total. Mostra quantos itens já fecharam, sem peso.
            </>,
          ]}
        />
      </>
    ),
  },
  {
    id: 'papeis',
    title: 'Papéis e permissões',
    body: (
      <>
        <P>Cada pessoa num workspace tem um papel, e o papel decide o que ela pode fazer:</P>
        <div className="flex flex-wrap gap-2">
          <Badge status="accent">Dono</Badge>
          <Badge status="success">Editor</Badge>
          <Badge status="na">Visualizador</Badge>
        </div>
        <div className="max-w-[68ch] overflow-x-auto">
          <table className="w-full border-collapse text-left">
            <caption className="sr-only">O que cada papel pode fazer</caption>
            <thead>
              <tr className="border-b">
                <th scope="col" className="label-sm py-2 pr-3 font-medium text-text-muted">
                  Ação
                </th>
                <th scope="col" className="label-sm px-2 py-2 text-center font-medium text-text-muted">
                  Dono
                </th>
                <th scope="col" className="label-sm px-2 py-2 text-center font-medium text-text-muted">
                  Editor
                </th>
                <th scope="col" className="label-sm px-2 py-2 text-center font-medium text-text-muted">
                  Visualizador
                </th>
              </tr>
            </thead>
            <tbody className="label-md">
              {[
                ['Ver tudo', true, true, true],
                ['Registrar avanço', true, true, false],
                ['Criar e editar projetos, células, robôs e tarefas', true, true, false],
                ['Atribuir responsáveis', true, true, false],
                ['Convidar pessoas', true, true, false],
                ['Excluir cards e resetar o workspace', true, false, false],
              ].map(([acao, dono, editor, viewer]) => (
                <tr key={acao as string} className="border-b border-border/60">
                  <th scope="row" className="py-2 pr-3 font-normal text-text-main">
                    {acao}
                  </th>
                  {[dono, editor, viewer].map((can, i) => (
                    <td key={i} className="px-2 py-2 text-center">
                      {can ? (
                        <span className="font-medium text-success-ink">Sim</span>
                      ) : (
                        <span className="text-text-muted">
                          <span aria-hidden="true">—</span>
                          <span className="sr-only">não</span>
                        </span>
                      )}
                    </td>
                  ))}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        <P>
          Quem autoriza é sempre o servidor: a tela apenas esconde o que você não pode fazer. Se um botão não
          aparece para você, é porque o seu papel não permite aquela ação.
        </P>
      </>
    ),
  },
  {
    id: 'navegar',
    title: 'Navegando pelo app',
    body: (
      <>
        <P>
          A barra lateral tem três destinos fixos. O resto (Configurações, Ajuda, conta) mora no menu da conta,
          no canto inferior esquerdo, e nesta barra do topo.
        </P>
        <Steps
          items={[
            <>
              <Term>Visão Geral</Term> — seus projetos, cada um com as duas medidas de progresso. É a porta de
              entrada.
            </>,
            <>
              <Term>Projeto → Célula</Term> — desça a hierarquia tocando nos cards para chegar aos robôs.
            </>,
            <>
              <Term>Tela do robô</Term> — a tabela de tarefas, onde o trabalho acontece. As tarefas ficam em grupos
              que abrem e fecham, com colunas de status, progresso, responsáveis e histórico.
            </>,
            <>
              <Term>Minhas Tarefas</Term> — só as tarefas atribuídas a você, reunidas de todos os robôs.
            </>,
            <>
              <Term>Relatório</Term> — o Protocolo de Comissionamento, pronto para imprimir.
            </>,
            <>
              <Term>Configurações</Term> — pessoas responsáveis, tarefas-base, aparência, equipe/convites e (para o
              dono) backup e reset.
            </>,
          ]}
        />
      </>
    ),
  },
  {
    id: 'montar',
    title: 'Montando a estrutura',
    body: (
      <>
        <P>
          O dono ou um editor monta a hierarquia de cima para baixo. Em cada tela há o botão para adicionar o
          nível de baixo:
        </P>
        <Steps
          items={[
            <>
              Na Visão Geral, use <Term>Novo Projeto</Term>.
            </>,
            <>
              Dentro do projeto, use <Term>Nova célula</Term>.
            </>,
            <>
              Dentro da célula, use <Term>Adicionar robôs</Term>.
            </>,
          ]}
        />
        <P>
          Ao adicionar robôs, um assistente de dois passos permite criar <Term>vários de uma vez</Term> — de 1 a
          50 — informando a quantidade e a aplicação. Cada robô já nasce com as tarefas-base do catálogo que valem
          para aquela aplicação.
        </P>
        <P>
          Na tela do robô, o editor pode <Term>Adicionar tarefa</Term> avulsa, editar as existentes e usar{' '}
          <Term>Sincronizar tarefas-base</Term> para trazer as tarefas do catálogo que ainda faltam naquele robô.
          O catálogo em si é gerenciado em Configurações → Tarefas-base.
        </P>
      </>
    ),
  },
  {
    id: 'avanco',
    title: 'Registrando o avanço de uma tarefa',
    body: (
      <>
        <P>É a ação mais comum no dia a dia, e leva segundos:</P>
        <Steps
          items={[
            <>Na tela do robô, mexa no controle de progresso da tarefa.</>,
            <>
              Arraste até a porcentagem real. Ao <Term>soltar</Term>, abre a janela <Term>Registrar avanço</Term>.
            </>,
            <>
              Abaixo de 100%, o <Term>comentário é obrigatório</Term> (diga o que foi feito ou o que falta). Ao
              chegar a 100%, o comentário é opcional.
            </>,
            <>
              Toque em <Term>Registrar</Term>. O avanço entra no histórico da tarefa — que não pode ser apagado — e
              o progresso do robô, da célula e do projeto se recalcula na hora.
            </>,
          ]}
        />
        <P>
          O status acompanha o número: <Term>Pendente</Term> em 0%, <Term>Em Andamento</Term> entre 1% e 99% e{' '}
          <Term>Concluída</Term> em 100%. Trocar o status também passa pela mesma janela de avanço.
        </P>
        <P>
          O RoboTrack é honesto sobre o que salvou: só diz “salvo” quando salvou de verdade. Sem internet, o
          avanço fica pendente na fila e sincroniza quando a rede voltar (veja “Usando sem internet”).
        </P>
      </>
    ),
  },
  {
    id: 'responsaveis',
    title: 'Atribuindo responsáveis',
    body: (
      <>
        <P>
          Na tela do robô, a coluna <Term>Responsáveis</Term> define quem cuida de cada tarefa. A atribuição é{' '}
          <Term>por pessoa</Term>: marque as pessoas na lista — e, se ela ainda não existe, cadastre-a ali mesmo.
          Uma tarefa pode ter mais de um responsável.
        </P>
        <P>
          Quem é responsável recebe notificação dos avanços daquela tarefa e a vê em <Term>Minhas Tarefas</Term>.
          As pessoas também podem ser cadastradas e organizadas em Configurações → Responsáveis.
        </P>
      </>
    ),
  },
  {
    id: 'convites',
    title: 'Convidando pessoas',
    body: (
      <>
        <P>
          Convites funcionam por <Term>código</Term>. Quem gerencia (dono ou editor) usa <Term>Convidar pessoa</Term>{' '}
          na barra do topo, escolhe o papel (Editor ou Visualizador) e recebe um código curto, no formato{' '}
          <Term>XXXX-XXXX</Term>. Basta passar esse código para a pessoa.
        </P>
        <P>Quem recebeu o código entra de duas formas:</P>
        <Steps
          items={[
            <>
              Ainda sem conta ou deslogada: na tela de entrada, em <Term>“Tenho um código de convite”</Term>.
            </>,
            <>
              Já logada em outro workspace: no menu da conta, na opção <Term>“{inviteText.joinByCodeMenu}”</Term>.
              O app troca para o novo workspace e abre a Visão Geral dele.
            </>,
          ]}
        />
      </>
    ),
  },
  {
    id: 'notificacoes',
    title: 'Notificações',
    body: (
      <>
        <P>
          O <Term>sino</Term> na barra do topo mostra quantas notificações você tem por ler; tocá-lo abre a
          central. Por padrão, você recebe avisos das tarefas em que é responsável.
        </P>
        <P>
          Além disso, no cabeçalho de cada projeto, célula e robô há um sino de <Term>preferência</Term>, com três
          opções:
        </P>
        <Steps
          items={[
            <>
              <Term>Seguir</Term> — receber os avanços daquele nível mesmo sem ser responsável.
            </>,
            <>
              <Term>Silenciar</Term> — não receber daquele nível.
            </>,
            <>
              <Term>Padrão</Term> — o comportamento normal (você recebe do que é responsável).
            </>,
          ]}
        />
        <P>
          Vale a regra do <Term>mais específico vence</Term>: se você silencia uma célula, cala os robôs dela — mas
          se seguir um robô específico dentro dela, volta a receber daquele robô. O sino sempre mostra o estado que
          está valendo e de onde ele vem.
        </P>
        <P>O dono recebe os avanços de todo o workspace dele, para acompanhar sem depender de estar atribuído.</P>
      </>
    ),
  },
  {
    id: 'offline',
    title: 'Usando sem internet',
    body: (
      <>
        <P>
          O RoboTrack é um app que funciona <Term>offline</Term>. Depois de abrir online pelo menos uma vez, ele
          continua funcionando sem rede:
        </P>
        <Steps
          items={[
            <>As leituras vêm do que já foi carregado (o que você viu enquanto estava online).</>,
            <>
              As escritas — avanços, edições — entram numa <Term>fila</Term> e sincronizam sozinhas quando a rede
              volta.
            </>,
            <>O app avisa quando está offline e quando há itens pendentes: você nunca acha que salvou sem salvar.</>,
          ]}
        />
        <P>
          A única exceção: <Term>entrar e criar conta precisam de internet</Term>. Uma vez dentro, o galpão sem
          sinal deixa de ser problema.
        </P>
      </>
    ),
  },
  {
    id: 'excluir',
    title: 'Excluindo itens',
    body: (
      <>
        <P>
          Só o <Term>Dono</Term> exclui projetos, células, robôs e tarefas. As formas de excluir:
        </P>
        <Steps
          items={[
            <>
              No computador: pelo ícone de <Term>lixeira</Term> no card ou na linha.
            </>,
            <>
              No celular: <Term>arraste o card para a esquerda</Term> para revelar o botão Excluir.
            </>,
          ]}
        />
        <P>
          Excluir sempre pede <Term>confirmação</Term> — nada some com um toque. Ao excluir um item, o que está
          abaixo dele também é arquivado (excluir um projeto arquiva suas células, robôs e tarefas). O histórico e a
          auditoria são preservados.
        </P>
      </>
    ),
  },
  {
    id: 'relatorio',
    title: 'Relatório de comissionamento',
    body: (
      <>
        <P>
          Em <Term>Relatório</Term>, o RoboTrack monta o <Term>Protocolo de Comissionamento</Term> — o documento
          formal que se assina no fim do trabalho. Ele consolida o progresso real de projetos, células e robôs.
        </P>
        <P>
          O documento é em formato <Term>A4</Term>, pronto para imprimir (ou salvar em PDF pela opção de impressão
          do navegador).
        </P>
      </>
    ),
  },
]

export function AjudaPage() {
  return (
    <div className="mx-auto max-w-5xl space-y-8 p-4">
      <header className="max-w-[68ch] space-y-2">
        <h1 className="title">Ajuda</h1>
        <p className="leading-relaxed text-text-muted">
          Como o RoboTrack funciona e como usar, do começo ao fim. Toque em uma seção para ir direto a ela.
        </p>
      </header>

      <div className="grid grid-cols-1 lg:grid-cols-[13rem_1fr] lg:gap-10">
        {/* Índice navegável. No desktop fica fixo ao rolar; no mobile é uma lista
            de atalhos acima do conteúdo. Âncoras dentro da própria página. */}
        <nav aria-label="Seções da ajuda" className="mb-8 lg:mb-0 lg:sticky lg:top-4 lg:self-start">
          <ol className="space-y-1">
            {SECTIONS.map((s, i) => (
              <li key={s.id}>
                <a
                  href={`#${s.id}`}
                  className="label-md flex items-baseline gap-2 rounded-md px-2 py-1.5 text-text-muted hover:bg-accent/10 hover:text-text-main"
                >
                  <span className="tabular w-4 shrink-0 text-right text-text-muted">{i + 1}</span>
                  <span>{s.title}</span>
                </a>
              </li>
            ))}
          </ol>
        </nav>

        <div className="min-w-0 space-y-12">
          {SECTIONS.map((s) => (
            <section key={s.id} id={s.id} aria-labelledby={`${s.id}-h`} className="scroll-mt-20 space-y-3">
              <h2 id={`${s.id}-h`} className="panel-header">
                {s.title}
              </h2>
              {s.body}
            </section>
          ))}
        </div>
      </div>
    </div>
  )
}
