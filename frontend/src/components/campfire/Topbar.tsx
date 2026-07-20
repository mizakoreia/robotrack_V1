import React from 'react'

import { useTheme } from '@/hooks/useTheme'

export function Topbar() {
  /* const APP_NAME = import.meta.env.VITE_APP_NAME || 'robotrack' */
  const { theme, setTheme } = useTheme()
  /* const { isAuthenticated } = useAuthStore()
  const [open, setOpen] = React.useState(false) */
  const [showOnMobile, setShowOnMobile] = React.useState(false)
  React.useEffect(() => {
    let headerVisible = false
    let footerVisible = false
    function updateState() { setShowOnMobile(headerVisible || footerVisible) }
    function onHeader(e: any) { headerVisible = !!(e.detail && e.detail.visible); updateState() }
    function onFooter(e: any) { footerVisible = !!(e.detail && e.detail.visible); updateState() }
    window.addEventListener('header:visible', onHeader)
    window.addEventListener('footer:visible', onFooter)
    return () => {
      window.removeEventListener('header:visible', onHeader)
      window.removeEventListener('footer:visible', onFooter)
    }
  }, [])
  return (
    <div className={`fixed top-0 left-0 right-0 z-50 ${showOnMobile ? 'block' : 'hidden'} md:block`}>
      <div className="bg-card/80 backdrop-blur-sm border-b h-[var(--topbar-h)]">
        <div className="max-w-6xl mx-auto h-full px-0 md:px-0 flex items-center justify-between">
          <div className="text-base md:text-lg font-bold text-foreground">@polemk/robotrack</div>
          <div className="flex items-center gap-[15px] max-w-full px-4 md:px-0 md:mr-4">
            <button
              aria-label="Alternar tema"
              role="switch"
              aria-checked={theme === 'dark'}
              onClick={() => setTheme(theme === 'dark' ? 'light' : 'dark')}
              className={`relative h-6 w-12 rounded-full border transition-all duration-300 ease-in-out flex items-center shadow-sm overflow-hidden ${theme === 'dark' ? 'bg-black/40' : 'bg-card/50'}`}
            >
              <span className={`absolute top-0.5 left-0.5 h-5 w-5 rounded-full transition-transform duration-200 ${theme === 'dark' ? 'translate-x-6 bg-white' : 'translate-x-0 bg-black'}`} />
            </button>
          </div>
        </div>
      </div>
    </div>
  )
}
