

export function WhatIsIt() {
  return (
    <section id="what" className="px-6 md:px-12 py-16 campfire-body">
      <div className="max-w-6xl mx-auto lg:pr-[var(--header-card-w)] grid grid-cols-1 lg:grid-cols-2 gap-8 items-start">
        <div className="pr-6">
          <h2 className="text-4xl md:text-5xl font-bold">What is it?</h2>
          <p className="mt-3 pr-4">
            Campfire‑style pitch: installable, self‑hosted system; invite people; rooms, mentions, DMs, mobile support.
            Basics done right. You own your data and can customize it.
          </p>
        </div>
        <div className="rounded-2xl border bg-card p-3 lg:ml-[-48px] lg:mr-[48px]">
          <div className="aspect-video w-full rounded-xl bg-black/10 dark:bg-white/5" />
        </div>
      </div>
    </section>
  )
}
