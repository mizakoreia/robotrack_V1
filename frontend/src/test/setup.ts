import '@testing-library/jest-dom'
import { vi } from 'vitest'

try {
  if (typeof navigator !== 'undefined') {
    const existingClipboard = (navigator as any).clipboard
    if (existingClipboard) {
      existingClipboard.writeText = vi.fn()
    } else {
      Object.defineProperty(navigator, 'clipboard', {
        value: { writeText: vi.fn() },
        configurable: true,
        writable: true
      })
    }
  }
} catch {}

Object.defineProperty(window, 'location', {
  value: Object.assign(new URL('http://localhost/'), {
    assign: vi.fn(),
    reload: vi.fn()
  }),
  writable: true
})