// app-shell-navigation 4.1 (§3.10) — STUB do destino "Visão Geral". A árvore da
// hierarquia (projetos → células → robôs) é entregue por `hierarchy-screens`;
// aqui fica só o ponto de montagem, para a casca ter conteúdo navegável.
export function OverviewPage() {
  return (
    <section aria-labelledby="overview-title" className="mx-auto max-w-5xl">
      <h1 id="overview-title" className="title mb-2">
        Visão Geral
      </h1>
      <p className="text-text-muted">
        A árvore de projetos, células e robôs aparece aqui.
      </p>
    </section>
  )
}
