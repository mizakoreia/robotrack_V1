import React from 'react'

export function PageHeader({ title, subtitle, rightSlot }: { title: string; subtitle?: string; rightSlot?: React.ReactNode }) {
  return (
    <div className="flex items-center justify-between mt-3 mb-6">
      <div>
        <h1 className="text-2xl font-semibold mb-1">{title}</h1>
        {subtitle && (
          <p className="text-sm text-muted-foreground">{subtitle}</p>
        )}
      </div>
      {rightSlot && (
        <div className="flex items-center gap-2">{rightSlot}</div>
      )}
    </div>
  )
}

export default PageHeader