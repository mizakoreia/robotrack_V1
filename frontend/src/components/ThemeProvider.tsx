import React from 'react'
import { useTheme } from '@/hooks/useTheme'
/* import { Moon, Sun } from 'lucide-react' */

interface ThemeProviderProps {
  children: React.ReactNode
}

export function ThemeProvider({ children }: ThemeProviderProps) {
  useTheme()
  return <>{children}</>
}