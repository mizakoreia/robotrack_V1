import React from 'react'
import gsap from 'gsap'

export function FooterCrowd() {
  const canvasRef = React.useRef<HTMLCanvasElement | null>(null)
  React.useEffect(() => {
    const canvas = canvasRef.current!
    const ctx = canvas.getContext('2d')!
    const img = document.createElement('img')
    const stage = { width: 0, height: 0 }
    const allPeeps: Peep[] = []
    const availablePeeps: Peep[] = []
    const crowd: Peep[] = []
    /* let rafId = 0 */
    function randomRange(min: number, max: number) { return min + Math.random() * (max - min) }
    function randomIndex<T>(array: T[]) { return (randomRange(0, array.length) | 0) }
    function removeFromArray<T>(array: T[], i: number) { return array.splice(i, 1)[0] }
    function removeItemFromArray<T>(array: T[], item: T) { return removeFromArray(array, array.indexOf(item)) }
    function removeRandomFromArray<T>(array: T[]) { return removeFromArray(array, randomIndex(array)) }
    function getRandomFromArray<T>(array: T[]) { return array[randomIndex(array) | 0] }
    /* function easeInQuad(t: number) { return t * t } */
    class Peep {
      image: HTMLImageElement
      rect: number[]
      width: number
      height: number
      x = 0
      y = 0
      anchorY = 0
      scaleX = 1
      walk: gsap.core.Timeline | null = null
      drawArgs: any[]
      constructor({ image, rect }: { image: HTMLImageElement; rect: number[] }) {
        this.image = image
        this.rect = rect
        this.width = rect[2]
        this.height = rect[3]
        this.drawArgs = [this.image, ...rect, 0, 0, this.width, this.height]
      }
      render(context: CanvasRenderingContext2D) {
        context.save()
        context.translate(this.x, this.y)
        context.scale(this.scaleX, 1)
        const drawFunc: any = context.drawImage
        drawFunc.call(context, ...this.drawArgs)
        context.restore()
      }
    }
    function resetPeep({ stage, peep }: { stage: { width: number; height: number }; peep: Peep }) {
      const direction = Math.random() > 0.5 ? 1 : -1
      const offsetY = 100 - 250 * gsap.parseEase('power2.in')(Math.random())
      const startY = stage.height - peep.height + offsetY
      let startX: number
      let endX: number
      if (direction === 1) { startX = -peep.width; endX = stage.width; peep.scaleX = 1 } else { startX = stage.width + peep.width; endX = 0; peep.scaleX = -1 }
      peep.x = startX
      peep.y = startY
      peep.anchorY = startY
      return { startX, startY, endX }
    }
    function normalWalk({ peep, props }: { peep: Peep; props: { startX: number; startY: number; endX: number } }) {
      const { startY, endX } = props
      const xDuration = 10
      const yDuration = 0.25
      const tl = gsap.timeline()
      tl.timeScale(randomRange(0.5, 1.5))
      tl.to(peep, { duration: xDuration, x: endX, ease: 'none' }, 0)
      tl.to(peep, { duration: yDuration, repeat: xDuration / yDuration, yoyo: true, y: startY - 10 }, 0)
      return tl
    }
    const walks = [normalWalk]
    function addPeepToCrowd() {
      const peep = removeRandomFromArray(availablePeeps)
      const walk = getRandomFromArray(walks)({ peep, props: resetPeep({ peep, stage }) })
        .eventCallback('onComplete', () => { removePeepFromCrowd(peep); addPeepToCrowd() })
      peep.walk = walk
      crowd.push(peep)
      crowd.sort((a, b) => a.anchorY - b.anchorY)
      return peep
    }
    function removePeepFromCrowd(peep: Peep) {
      removeItemFromArray(crowd, peep)
      availablePeeps.push(peep)
    }
    function createPeeps() {
      const rows = 15
      const cols = 7
      const { naturalWidth: width, naturalHeight: height } = img
      const total = rows * cols
      const rectWidth = width / rows
      const rectHeight = height / cols
      for (let i = 0; i < total; i++) {
        allPeeps.push(new Peep({ image: img, rect: [(i % rows) * rectWidth, (i / rows | 0) * rectHeight, rectWidth, rectHeight] }))
      }
    }
    function initCrowd() {
      while (availablePeeps.length) {
        const peep = addPeepToCrowd()
        peep.walk!.progress(Math.random())
      }
    }
    function resize() {
      stage.width = canvas.clientWidth
      stage.height = canvas.clientHeight
      canvas.width = stage.width * devicePixelRatio
      canvas.height = stage.height * devicePixelRatio
      crowd.forEach((peep) => { peep.walk?.kill() })
      crowd.length = 0
      availablePeeps.length = 0
      availablePeeps.push(...allPeeps)
      initCrowd()
    }
    function render() {
      // Clear using the original technique to avoid trails
      canvas.width = canvas.width
      ctx.save()
      ctx.scale(devicePixelRatio, devicePixelRatio)
      crowd.forEach((peep) => { peep.render(ctx) })
      ctx.restore()
    }
    function start() {
      createPeeps()
      resize()
      gsap.ticker.add(render)
      window.addEventListener('resize', resize)
    }
    img.onload = start
    img.src = 'https://s3-us-west-2.amazonaws.com/s.cdpn.io/175711/open-peeps-sheet.png'
    // Footer visibility observer
    const container = document.getElementById('footer-crowd-container')
    let observer: IntersectionObserver | null = null
    if (container) {
      observer = new IntersectionObserver((entries) => {
        const entry = entries[0]
        window.dispatchEvent(new CustomEvent('footer:visible', { detail: { visible: entry.isIntersecting } }))
      }, { threshold: 0.2 })
      observer.observe(container)
    }
    return () => { gsap.ticker.remove(render); window.removeEventListener('resize', resize); observer?.disconnect() }
  }, [])
  return (
    <footer className="mt-10 bg-white text-slate-900 overflow-hidden">
      <div id="footer-crowd-container" className="relative w-screen h-[100vh] overflow-hidden">
        <div className="absolute top-0 md:top-[var(--topbar-h)] left-0 px-6 md:px-12 py-6">
          <div className="space-y-2">
            <div className="text-xs md:text-sm">{new Date().getFullYear()} © RoboTrack - Todos os direitos reservados.</div>
            <div className="text-2xl md:text-3xl font-bold">Construído por makers que chegaram<br/>muito antes do seu claudinho.</div>
            <div className="flex items-center gap-4 text-sm">
              <a href="/login" className="underline">Acessar</a>
              <a href="/dashboard" className="underline">Dashboard</a>
            </div>
          </div>
        </div>
        <canvas ref={canvasRef} id="canvas" className="block w-screen h-full" />
      </div>
    </footer>
  )
}
