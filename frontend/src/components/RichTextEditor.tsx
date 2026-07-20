import { useEffect, useMemo, useState } from 'react'
import { createEditor, Descendant, Editor, Element as SlateElement, Transforms, Range } from 'slate'
import { Slate, Editable, withReact } from 'slate-react'
import { withHistory } from 'slate-history'
import { Button } from '@/components/ui/Button'
import { Bold, Italic, Underline, Heading1, Heading2, List, Code, Link as LinkIcon, X } from 'lucide-react'

type CustomText = { text: string; bold?: boolean; italic?: boolean; underline?: boolean; code?: boolean }
type ParagraphElement = { type: 'paragraph'; children: CustomText[] }
type H1Element = { type: 'heading-one'; children: CustomText[] }
type H2Element = { type: 'heading-two'; children: CustomText[] }
type BulletedListElement = { type: 'bulleted-list'; children: ListItemElement[] }
type ListItemElement = { type: 'list-item'; children: CustomText[] }
type LinkElement = { type: 'link'; url: string; children: CustomText[] }
type CodeBlockElement = { type: 'code'; children: CustomText[] }
type CustomElement = ParagraphElement | H1Element | H2Element | BulletedListElement | ListItemElement | LinkElement | CodeBlockElement

function isMarkActive(editor: any, mark: keyof CustomText) {
  const marks = Editor.marks(editor) as Partial<CustomText> | null
  return !!marks && !!(marks as any)[mark]
}

function toggleMark(editor: any, mark: keyof CustomText) {
  if (isMarkActive(editor, mark)) {
    Editor.removeMark(editor, mark)
  } else {
    Editor.addMark(editor, mark, true)
  }
}

function isBlockActive(editor: any, type: CustomElement['type']) {
  const [match] = Array.from(Editor.nodes(editor, { match: (n: any) => SlateElement.isElement(n) && (n as any).type === type }))
  return !!match
}

function toggleBlock(editor: any, type: CustomElement['type']) {
  const isActive = isBlockActive(editor, type)
  Transforms.unwrapNodes(editor, { match: (n: any) => SlateElement.isElement(n) && (n as any).type === 'bulleted-list', split: true })
  const newType = isActive ? 'paragraph' : type
  Transforms.setNodes(editor, { type: newType } as any)
  if (type === 'bulleted-list' && !isActive) {
    Transforms.wrapNodes(editor, { type: 'bulleted-list', children: [] } as any)
    Transforms.setNodes(editor, { type: 'list-item' } as any)
  }
}

function isLinkActive(editor: any) {
  const [link] = Array.from(Editor.nodes(editor, { match: (n: any) => SlateElement.isElement(n) && (n as any).type === 'link' }))
  return !!link
}

function unwrapLink(editor: any) {
  Transforms.unwrapNodes(editor, { match: (n: any) => SlateElement.isElement(n) && (n as any).type === 'link' })
}

function wrapLink(editor: any, url: string) {
  if (isLinkActive(editor)) unwrapLink(editor)
  const { selection } = editor
  if (selection && Range.isCollapsed(selection)) {
    Transforms.insertNodes(editor, [{ type: 'link', url, children: [{ text: url }] } as any])
  } else {
    const link: LinkElement = { type: 'link', url, children: [{ text: '' }] }
    Transforms.wrapNodes(editor, link as any, { split: true })
  }
}

function clearFormatting(editor: any) {
  if (!editor.selection) return
  ;(['bold','italic','underline','code'] as const).forEach((m) => Editor.removeMark(editor, m as any))
  Transforms.unwrapNodes(editor, { match: (n: any) => SlateElement.isElement(n) && ((n as any).type === 'link' || (n as any).type === 'bulleted-list'), split: true })
  Transforms.setNodes(editor, { type: 'paragraph' } as any, { match: (n: any) => SlateElement.isElement(n) && ((n as any).type === 'heading-one' || (n as any).type === 'heading-two' || (n as any).type === 'list-item' || (n as any).type === 'code') })
}

function serializeToHTML(nodes: Descendant[]): string {
  function serializeNode(n: Descendant): string {
    if ('text' in n) {
      let text = (n as any).text
      const t = n as CustomText
      if (t.bold) text = `<strong>${text}</strong>`
      if (t.italic) text = `<em>${text}</em>`
      if (t.underline) text = `<u>${text}</u>`
      if (t.code) text = `<code>${text}</code>`
      return text
    }
    const el = n as any
    const children = (el.children as any[]).map(serializeNode).join('')
    switch (el.type) {
      case 'paragraph': return `<p>${children}</p>`
      case 'heading-one': return `<h1>${children}</h1>`
      case 'heading-two': return `<h2>${children}</h2>`
      case 'bulleted-list': return `<ul>${children}</ul>`
      case 'list-item': return `<li>${children}</li>`
      case 'link': return `<a href="${(el as LinkElement).url}">${children}</a>`
      case 'code': return `<pre><code>${children}</code></pre>`
      default: return children
    }
  }
  return nodes.map(serializeNode).join('')
}

function deserializeHTML(html: string): Descendant[] {
  const parser = new DOMParser()
  const decodeHTML = (s: string) => (s || '')
    .replace(/&lt;/g, '<').replace(/&gt;/g, '>')
    .replace(/&amp;/g, '&').replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'").replace(/&nbsp;/g, ' ')
  const doc = parser.parseFromString(decodeHTML(html) || '<p></p>', 'text/html')
  function deserialize(el: Node, marks: Partial<CustomText> = {}, preserveWhitespace = false): Descendant[] {
    if (el.nodeType === 3) {
      const raw = (el.textContent || '').replace(/\r/g, '')
      const noNewlines = preserveWhitespace ? raw : raw.replace(/\n/g, '')
      if (!preserveWhitespace && noNewlines.trim().length === 0) return []
      return [{ text: noNewlines, ...marks } as any]
    }
    if (!(el instanceof HTMLElement)) return []
    const nextMarks = { ...marks }
    const tag = el.tagName.toLowerCase()
    const nextPreserve = preserveWhitespace || tag === 'pre'
    if (tag === 'strong' || tag === 'b') nextMarks.bold = true
    if (tag === 'em' || tag === 'i') nextMarks.italic = true
    if (tag === 'u') nextMarks.underline = true
    if (tag === 'code' && el.parentElement?.tagName.toLowerCase() !== 'pre') nextMarks.code = true
    let children = Array.from(el.childNodes).flatMap(child => deserialize(child, nextMarks, nextPreserve))
    const ensureTextChildren = (nodes: Descendant[]) => nodes.length ? nodes : [{ text: '' } as any]
    switch (tag) {
      case 'h1': return [{ type: 'heading-one', children: ensureTextChildren(children) } as any]
      case 'h2': return [{ type: 'heading-two', children: ensureTextChildren(children) } as any]
      case 'ul': {
        const items: Descendant[] = []
        Array.from(el.children).forEach((li) => {
          if (li.tagName.toLowerCase() === 'li') {
            const liChildren = Array.from(li.childNodes).flatMap(child => deserialize(child, nextMarks, nextPreserve))
            items.push({ type: 'list-item', children: ensureTextChildren(liChildren) } as any)
          }
        })
        const ensured = items.length ? items : [{ type: 'list-item', children: [{ text: '' }] } as any]
        return [{ type: 'bulleted-list', children: ensured as any } as any]
      }
      case 'li': return [{ type: 'list-item', children: ensureTextChildren(children) } as any]
      case 'a': return [{ type: 'link', url: el.getAttribute('href') || '', children: children.length ? children : [{ text: el.getAttribute('href') || '' }] } as any]
      case 'pre': return [{ type: 'code', children: ensureTextChildren(children) } as any]
      case 'p': return [{ type: 'paragraph', children: ensureTextChildren(children) } as any]
      default:
        if (tag === 'br') return preserveWhitespace ? [{ text: '\n' } as any] : []
        return children
    }
  }
  const bodyChildren = Array.from(doc.body.childNodes)
  const result = bodyChildren.flatMap(n => deserialize(n))
  const normalized = result
    .map((n: any) => ('text' in n ? { type: 'paragraph', children: [n] } as any : n))
    .filter((n: any, idx: number) => {
      if (!n || !('children' in n)) return true
      const ch: any[] = (n.children || [])
      const onlyEmptyText = ch.length === 1 && 'text' in ch[0] && (ch[0].text || '') === ''
      return idx === 0 ? !onlyEmptyText : true
    })
  return normalized.length ? normalized : [{ type: 'paragraph', children: [{ text: '' }] } as any]
}

export default function RichTextEditor({ value, onChange, placeholder = 'Escreva...' }: { value: string; onChange: (v: string) => void; placeholder?: string }) {
  const [editor] = useState(() => {
    const e = withHistory(withReact(createEditor())) as any
    const prevIsInline = e.isInline
    e.isInline = (element: any) => (element?.type === 'link') || prevIsInline(element)
    return e
  })
  const [content, setContent] = useState<Descendant[]>(deserializeHTML(value))
  const [version, setVersion] = useState(0)
  useEffect(() => { setContent(deserializeHTML(value)); setVersion((v) => v + 1) }, [value])
  const renderElement = useMemo(() => (props: any) => {
    const { element, attributes, children } = props
    switch (element.type) {
      case 'heading-one': return <h1 {...attributes} className="text-lg font-semibold mb-2">{children}</h1>
      case 'heading-two': return <h2 {...attributes} className="text-base font-semibold mb-2">{children}</h2>
      case 'bulleted-list': return <ul {...attributes} className="list-disc pl-6">{children}</ul>
      case 'list-item': return <li {...attributes}>{children}</li>
      case 'link': return <a {...attributes} href={(element as LinkElement).url} className="text-primary underline">{children}</a>
      case 'code': return <pre {...attributes} className="bg-muted p-2 rounded text-xs overflow-auto"><code>{children}</code></pre>
      default: return <p {...attributes} className="mb-2">{children}</p>
    }
  }, [])
  const renderLeaf = useMemo(() => (props: any) => {
    const { leaf, attributes } = props
    let children = props.children
    if (leaf.bold) children = <strong>{children}</strong>
    if (leaf.italic) children = <em>{children}</em>
    if (leaf.underline) children = <u>{children}</u>
    if (leaf.code) children = <code className="bg-muted px-1 rounded text-xs">{children}</code>
    return <span {...attributes}>{children}</span>
  }, [])
  const onKeyDown = (e: React.KeyboardEvent) => {
    if (!e.ctrlKey) return
    if (e.key === 'b') { e.preventDefault(); toggleMark(editor, 'bold') }
    if (e.key === 'i') { e.preventDefault(); toggleMark(editor, 'italic') }
    if (e.key === 'u') { e.preventDefault(); toggleMark(editor, 'underline') }
    if (e.key === '`') { e.preventDefault(); toggleMark(editor, 'code') }
  }
  const isEmpty = useMemo(() => {
    if (!content || content.length === 0) return true
    if (content.length === 1) {
      const n: any = content[0]
      const children = (n?.children || []) as any[]
      if (children.length === 0) return true
      if (children.length === 1 && 'text' in children[0] && (children[0].text || '') === '') return true
    }
    return false
  }, [content])
  return (
    <div>
      <div className="flex gap-2 mb-2 -mt-2">
        <Button aria-label="Negrito" variant="ghost" size="icon" className="h-8 w-8" onMouseDown={(e) => e.preventDefault()} onClick={() => toggleMark(editor, 'bold')}><Bold className="h-4 w-4" /></Button>
        <Button aria-label="Itálico" variant="ghost" size="icon" className="h-8 w-8" onMouseDown={(e) => e.preventDefault()} onClick={() => toggleMark(editor, 'italic')}><Italic className="h-4 w-4" /></Button>
        <Button aria-label="Sublinhado" variant="ghost" size="icon" className="h-8 w-8" onMouseDown={(e) => e.preventDefault()} onClick={() => toggleMark(editor, 'underline')}><Underline className="h-4 w-4" /></Button>
        <Button aria-label="Título 1" variant="ghost" size="icon" className="h-8 w-8" onMouseDown={(e) => e.preventDefault()} onClick={() => toggleBlock(editor, 'heading-one')}><Heading1 className="h-4 w-4" /></Button>
        <Button aria-label="Título 2" variant="ghost" size="icon" className="h-8 w-8" onMouseDown={(e) => e.preventDefault()} onClick={() => toggleBlock(editor, 'heading-two')}><Heading2 className="h-4 w-4" /></Button>
        <Button aria-label="Lista" variant="ghost" size="icon" className="h-8 w-8" onMouseDown={(e) => e.preventDefault()} onClick={() => toggleBlock(editor, 'bulleted-list')}><List className="h-4 w-4" /></Button>
        <Button aria-label="Código" variant="ghost" size="icon" className="h-8 w-8" onMouseDown={(e) => e.preventDefault()} onClick={() => toggleBlock(editor, 'code')}><Code className="h-4 w-4" /></Button>
        <Button aria-label="Link" variant="ghost" size="icon" className="h-8 w-8" onMouseDown={(e) => e.preventDefault()} onClick={() => { const url = window.prompt('URL'); if (url) wrapLink(editor, url) }}><LinkIcon className="h-4 w-4" /></Button>
        <Button aria-label="Limpar formatação" variant="ghost" size="icon" className="h-8 w-8" onMouseDown={(e) => e.preventDefault()} onClick={() => clearFormatting(editor)}><X className="h-4 w-4" /></Button>
      </div>
      <div className="relative">
        {isEmpty && (
          <div className="absolute left-3 top-3 text-sm text-muted-foreground pointer-events-none select-none">{placeholder}</div>
        )}
        <Slate key={version} editor={editor} initialValue={content} onChange={(v) => { setContent(v); onChange(serializeToHTML(v)) }}>
          <Editable
            renderElement={renderElement as any}
            renderLeaf={renderLeaf as any}
            onKeyDown={onKeyDown}
            className="w-full min-h-[160px] p-3 text-sm text-foreground bg-background border border-border rounded-md outline-none"
            spellCheck={false}
          />
        </Slate>
      </div>
    </div>
  )
}

