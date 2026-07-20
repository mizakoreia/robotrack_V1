

export function SystemRequirements() {
  return (
    <section id="requirements" className="px-6 md:px-12 py-16 campfire-body">
      <div className="max-w-6xl mx-auto lg:pr-[420px]">
        <h2 className="text-4xl md:text-5xl font-bold">System requirements & installation</h2>
        <div className="mt-6 overflow-x-auto">
          <table className="min-w-full text-left text-sm">
            <thead>
              <tr className="text-muted-foreground">
                <th className="py-2 px-3">Concurrent Users</th>
                <th className="py-2 px-3">RAM</th>
                <th className="py-2 px-3">CPU</th>
              </tr>
            </thead>
            <tbody>
              <tr className="border-t">
                <td className="py-2 px-3">250</td>
                <td className="py-2 px-3">2GB</td>
                <td className="py-2 px-3">1CPU</td>
              </tr>
              <tr className="border-t">
                <td className="py-2 px-3">1,000</td>
                <td className="py-2 px-3">8GB</td>
                <td className="py-2 px-3">4CPU</td>
              </tr>
              <tr className="border-t">
                <td className="py-2 px-3">5,000</td>
                <td className="py-2 px-3">32GB</td>
                <td className="py-2 px-3">6CPU</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </section>
  )
}
