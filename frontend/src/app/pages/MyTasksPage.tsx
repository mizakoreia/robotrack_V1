// app-shell-navigation 4.1 (§3.10) — STUB do destino "Minhas Tarefas". A lista
// pessoal com filtros é entregue por `my-tasks-view`; aqui só o ponto de montagem.
export function MyTasksPage() {
  return (
    <section aria-labelledby="my-tasks-title" className="mx-auto max-w-5xl">
      <h1 id="my-tasks-title" className="title mb-2">
        Minhas Tarefas
      </h1>
      <p className="text-text-muted">Suas tarefas atribuídas aparecem aqui.</p>
    </section>
  )
}
