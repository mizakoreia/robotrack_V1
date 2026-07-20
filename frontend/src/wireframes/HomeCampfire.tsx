

export function HomeCampfireWireframes() {
  return (
    <div className="px-6 md:px-12 py-10 space-y-8">
      <div className="text-sm text-muted-foreground">Wireframes (Desktop/Tablet/Mobile)</div>
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <div className="rounded-xl border p-4">
          <div className="font-medium mb-2">Desktop</div>
          <div className="h-64 bg-muted rounded-md" />
        </div>
        <div className="rounded-xl border p-4">
          <div className="font-medium mb-2">Tablet</div>
          <div className="h-64 bg-muted rounded-md" />
        </div>
        <div className="rounded-xl border p-4">
          <div className="font-medium mb-2">Mobile</div>
          <div className="h-64 bg-muted rounded-md" />
        </div>
      </div>
    </div>
  )
}

