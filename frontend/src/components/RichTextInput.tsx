import { useEffect, useState } from 'react'

export function RichTextInput({ value, displayHtml, onChange }: { value: string; displayHtml?: string; onChange: (v: string) => void }) {
  const [isRich, setIsRich] = useState(false)
  const [text, setText] = useState(value || '')
  const [html, setHtml] = useState(displayHtml || '')

  useEffect(() => {
    setText(value || '')
  }, [value])

  useEffect(() => {
    setHtml(displayHtml || '')
  }, [displayHtml])

  return (
    <div className="space-y-2">
      <div className="flex items-center gap-2">
        <button type="button" className="text-xs px-2 py-1 rounded-md border border-input hover:bg-accent" onClick={() => setIsRich(false)}>Texto</button>
        <button type="button" className="text-xs px-2 py-1 rounded-md border border-input hover:bg-accent" onClick={() => setIsRich(true)}>WYSIWYG</button>
      </div>
      {!isRich ? (
        <textarea
          className="rounded-[12px] border border-input bg-background p-3 text-sm text-foreground min-h-[120px]"
          value={text}
          onChange={(e) => { setText(e.target.value); onChange(e.target.value) }}
          placeholder="Digite o conteúdo"
        />
      ) : (
        <div
          className="rounded-[12px] border border-input bg-background p-3 text-sm text-foreground min-h-[120px]"
          contentEditable
          suppressContentEditableWarning
          onInput={(e) => {
            const val = (e.target as HTMLElement).innerHTML
            setHtml(val)
            onChange(val)
          }}
          dangerouslySetInnerHTML={{ __html: html || text.replace(/\n/g, '<br/>') }}
        />
      )}
    </div>
  )
}

export default RichTextInput

