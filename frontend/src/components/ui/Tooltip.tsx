import React from 'react'

interface TooltipProps {
  content: React.ReactNode
  side?: 'right' | 'left' | 'top' | 'bottom'
  children: React.ReactNode
}

export function Tooltip({ content, side = 'right', children }: TooltipProps) {
  const pos = {
    right: 'left-full ml-2 top-1/2 -translate-y-1/2',
    left: 'right-full mr-2 top-1/2 -translate-y-1/2',
    top: 'bottom-full mb-2 left-1/2 -translate-x-1/2',
    bottom: 'top-full mt-2 left-1/2 -translate-x-1/2',
  }[side]

  return (
    <div className="relative group inline-block">
      {children}
      <div
        role="tooltip"
        className={`pointer-events-none absolute ${pos} whitespace-nowrap rounded-md border border-border bg-popover px-2 py-1 text-xs text-popover-foreground shadow-sm opacity-0 group-hover:opacity-100 transition-opacity duration-150`}
      >
        {content}
      </div>
    </div>
  )
}
