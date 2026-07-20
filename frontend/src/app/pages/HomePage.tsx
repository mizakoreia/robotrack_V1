// HomePage component
import { useTheme } from '@/hooks/useTheme'
import { Topbar } from '@/components/campfire/Topbar'
import { HeroCampfire } from '@/components/campfire/HeroCampfire'
import { MediaShowcase } from '@/components/campfire/MediaShowcase'
import { WhatIsIt } from '@/components/campfire/sections/WhatIsIt'
import { WhyNotSlack } from '@/components/campfire/sections/WhyNotSlack'
import { TakeCloserLook } from '@/components/campfire/sections/TakeCloserLook'

import { FooterCrowd } from '@/components/campfire/FooterCrowd'

export function HomePage() {
  const { theme } = useTheme()

  return (
          <div className={`min-h-screen ${theme === 'dark' ? 'bg-[#0B0F1A]' : 'bg-white'}`}>
      <Topbar />
      <HeroCampfire />
      <MediaShowcase />
      <WhatIsIt />
      <TakeCloserLook />
      <WhyNotSlack />

      <FooterCrowd />
      <script dangerouslySetInnerHTML={{ __html: `
        (function(){
          function toggleFaq(e){
            var visible = e.detail && e.detail.visible;
            var el = document.getElementById('faq-hint');
            if (!el) return;
            el.style.display = visible ? 'none' : '';
          }
          window.addEventListener('footer:visible', toggleFaq);
        })();
      `}} />
    </div>
  )
}



