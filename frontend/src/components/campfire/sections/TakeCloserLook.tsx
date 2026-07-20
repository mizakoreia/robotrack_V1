

export function TakeCloserLook() {
  return (
    <section id="closer" className="px-6 md:px-12 py-16 campfire-body">
      <div className="max-w-6xl mx-auto lg:pr-[var(--header-card-w)]">
        <h2 className="text-4xl md:text-5xl font-bold">Take a closer look</h2>
        <div className="mt-6 grid grid-cols-1 lg:grid-cols-6 gap-4 mosaic-grid lg:mr-[48px]">
          {[1,2,3,4,5,6].map((n, idx) => (
            <div key={n} className="rounded-2xl border bg-card overflow-hidden mosaic-tile">
              <img
                src={`/assets/gallery/${n}.jpg`}
                loading={idx < 2 ? 'eager' : 'lazy'}
                decoding="async"
                alt={`gallery ${n}`}
                className="w-full h-full object-cover"
                onError={(e) => {
                  const target = e.currentTarget as HTMLImageElement
                  if (target.src.includes('placeholder.jpg')) return
                  target.src = '/assets/gallery/placeholder.jpg'
                }}
              />
            </div>
          ))}
        </div>
      </div>
    </section>
  )
}
