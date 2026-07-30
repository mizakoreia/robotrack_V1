import { Badge } from '@/components/ui/Badge'
import { progressText } from '@/lib/i18n/progress'
import { inviteText } from '@/lib/i18n/invitations'
import { ajudaText, type AjudaBlock, type AjudaRun } from '@/lib/i18n/ajuda'

// ajuda-screen — a tela de Ajuda (rota `/ajuda`), alcançável pelo "?" da topbar.
// Frontend puro, sem banco: descreve o app REAL no estado atual. A prosa (pt-BR +
// en) mora em `lib/i18n/ajuda.ts`, estruturada por dados: a MESMA lista de seções
// alimenta o índice navegável e as seções, então TOC e conteúdo nunca divergem —
// em nenhum idioma. Esta tela só mapeia essa estrutura para JSX.
//
// Legibilidade sob luz de galpão (PRODUCT §Design): corpo em `text-text-main`
// (nunca cinza-claro por elegância), medida de leitura contida (~68ch), degraus
// de tipografia nomeados (`.title`/`.panel-header`/`.label-md`). Sem card por
// enfeite (Princípio 5) — o ritmo vem do espaçamento e das réguas, não de caixas.

// Termo em destaque dentro da prosa (peso, não cor — evita ruído de cor semântica).
function Term({ children }: { children: React.ReactNode }) {
  return <strong className="font-semibold text-text-main">{children}</strong>
}

// Um trecho de texto rico: string simples, termo em negrito (`b`) ou rótulo vindo de
// OUTRO módulo i18n (`ref`) — as duas métricas de progresso e o item de menu de
// convite, que se resolvem no idioma corrente aqui.
function renderRun(run: AjudaRun, i: number): React.ReactNode {
  if (typeof run === 'string') return run
  if ('ref' in run) {
    if (run.ref === 'weighted') return <Term key={i}>{progressText.metrics.weighted.label}</Term>
    if (run.ref === 'raw_count') return <Term key={i}>{progressText.metrics.raw_count.label}</Term>
    return <Term key={i}>{`“${inviteText.joinByCodeMenu}”`}</Term>
  }
  return <Term key={i}>{run.b}</Term>
}

function Runs({ runs }: { runs: AjudaRun[] }) {
  return <>{runs.map(renderRun)}</>
}

// Bloco de prosa com medida de leitura contida e ritmo entre parágrafos.
function P({ runs }: { runs: AjudaRun[] }) {
  return (
    <p className="max-w-[68ch] leading-relaxed text-text-main">
      <Runs runs={runs} />
    </p>
  )
}

// Lista de passos/itens; marcadores discretos, texto no corpo legível.
function Steps({ items }: { items: AjudaRun[][] }) {
  return (
    <ul className="max-w-[68ch] space-y-1.5 text-text-main">
      {items.map((runs, i) => (
        <li key={i} className="flex gap-2 leading-relaxed">
          <span aria-hidden="true" className="mt-[0.55em] h-1.5 w-1.5 shrink-0 rounded-full bg-accent" />
          <span>
            <Runs runs={runs} />
          </span>
        </li>
      ))}
    </ul>
  )
}

// Padrão de permissão da matriz de papéis (dono/editor/viewer). É estrutural — não
// se traduz — e casa por índice com `ajudaText.roles.actions`.
const ROLE_MATRIX: [boolean, boolean, boolean][] = [
  [true, true, true],
  [true, true, false],
  [true, true, false],
  [true, true, false],
  [true, true, false],
  [true, false, false],
]

function RolesTable() {
  const { roles } = ajudaText
  return (
    <>
      <div className="flex flex-wrap gap-2">
        <Badge status="accent">{roles.badges.owner}</Badge>
        <Badge status="success">{roles.badges.editor}</Badge>
        <Badge status="na">{roles.badges.viewer}</Badge>
      </div>
      <div className="max-w-[68ch] overflow-x-auto">
        <table className="w-full border-collapse text-left">
          <caption className="sr-only">{roles.caption}</caption>
          <thead>
            <tr className="border-b">
              <th scope="col" className="label-sm py-2 pr-3 font-medium text-text-muted">
                {roles.actionHeader}
              </th>
              <th scope="col" className="label-sm px-2 py-2 text-center font-medium text-text-muted">
                {roles.badges.owner}
              </th>
              <th scope="col" className="label-sm px-2 py-2 text-center font-medium text-text-muted">
                {roles.badges.editor}
              </th>
              <th scope="col" className="label-sm px-2 py-2 text-center font-medium text-text-muted">
                {roles.badges.viewer}
              </th>
            </tr>
          </thead>
          <tbody className="label-md">
            {roles.actions.map((acao, row) => (
              <tr key={acao} className="border-b border-border/60">
                <th scope="row" className="py-2 pr-3 font-normal text-text-main">
                  {acao}
                </th>
                {ROLE_MATRIX[row].map((can, i) => (
                  <td key={i} className="px-2 py-2 text-center">
                    {can ? (
                      <span className="font-medium text-success-ink">{roles.yes}</span>
                    ) : (
                      <span className="text-text-muted">
                        <span aria-hidden="true">—</span>
                        <span className="sr-only">{roles.no}</span>
                      </span>
                    )}
                  </td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </>
  )
}

function renderBlock(block: AjudaBlock, i: number): React.ReactNode {
  if ('p' in block) return <P key={i} runs={block.p} />
  if ('steps' in block) return <Steps key={i} items={block.steps} />
  return <RolesTable key={i} />
}

export function AjudaPage() {
  const { sections } = ajudaText
  return (
    <div className="mx-auto max-w-5xl space-y-8 p-4">
      <header className="max-w-[68ch] space-y-2">
        <h1 className="title">{ajudaText.pageTitle}</h1>
        <p className="leading-relaxed text-text-muted">{ajudaText.pageIntro}</p>
      </header>

      <div className="grid grid-cols-1 lg:grid-cols-[13rem_1fr] lg:gap-10">
        {/* Índice navegável. No desktop fica fixo ao rolar; no mobile é uma lista
            de atalhos acima do conteúdo. Âncoras dentro da própria página. */}
        <nav aria-label={ajudaText.navLabel} className="mb-8 lg:mb-0 lg:sticky lg:top-4 lg:self-start">
          <ol className="space-y-1">
            {sections.map((s, i) => (
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
          {sections.map((s) => (
            <section key={s.id} id={s.id} aria-labelledby={`${s.id}-h`} className="scroll-mt-20 space-y-3">
              <h2 id={`${s.id}-h`} className="panel-header">
                {s.title}
              </h2>
              {s.body.map(renderBlock)}
            </section>
          ))}
        </div>
      </div>
    </div>
  )
}
