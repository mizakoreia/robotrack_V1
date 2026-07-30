import { describe, expect, it } from 'vitest'
import { readdirSync, readFileSync } from 'node:fs'
import { join } from 'node:path'

// app-shell-navigation 6.4 (D9) — a trava da convenção que roda no CI. Nomeia o
// arquivo ofensor, e é o que impede as seis capacidades de tela de inventarem seis
// convenções em paralelo. As regras concretas e verificáveis:
//   A. componentes/telas não importam `lib/api/client`/`endpoints` (leem por hooks
//      de domínio em `features/*/api/`);
//   B. `createPortal` só em `components/menu/` (+ `components/ui/Modal.tsx`, dialog);
//   C. stores de Zustand não buscam dado (não importam a camada de API);
//   D. nenhuma mutation invalida `['ws', wsId]` inteiro (só chaves específicas).
// Cada exceção pré-existente é uma allowlist DOCUMENTADA — nova violação falha.

const SRC = join(__dirname, '../src')

function walk(dir: string): string[] {
  return readdirSync(dir, { withFileTypes: true }).flatMap((e) => {
    const p = join(dir, e.name)
    if (e.isDirectory()) return walk(p)
    return /\.(ts|tsx)$/.test(e.name) && !/\.test\.|\.d\.ts$/.test(e.name) ? [p] : []
  })
}

function rel(p: string): string {
  return p.slice(SRC.length + 1).replace(/\\/g, '/')
}

const ALL = walk(SRC).map((p) => ({ path: rel(p), src: readFileSync(p, 'utf8') }))

describe('convenção D9 — regra A: componentes/telas não importam a camada de API', () => {
  // Dívida do template + infra não-domínio, congelada. `seal-template-baseline`
  // remove as páginas legadas; `authApi`/`countriesApi` são não-domínio (sessão e
  // metadados), não leituras de domínio. Nova tela de domínio que importe a API falha.
  const ALLOW = new Set([
    'components/ProtectedRoute.tsx', // authApi — guarda de sessão (não-domínio)
    'components/PhoneInputGroup.tsx', // apiClient — lookup de países (metadados)
    'app/pages/ProfilePage.tsx', // legado do template (seal-template-baseline)
    'app/pages/UsersPage.tsx', // legado do template (seal-template-baseline)
  ])

  it('nenhum componente/tela fora da allowlist importa lib/api/client|endpoints', () => {
    const offenders = ALL.filter(
      (f) =>
        (f.path.startsWith('components/') || f.path.startsWith('app/')) &&
        /from ['"]@\/lib\/api\/(client|endpoints)['"]/.test(f.src) &&
        !ALLOW.has(f.path),
    ).map((f) => f.path)
    expect(offenders, `importam a API direto (use um hook de features/*/api/): ${offenders.join(', ')}`).toEqual([])
  })
})

describe('convenção D9 — regra B: createPortal só em components/menu/ (+ Modal)', () => {
  it('createPortal não aparece fora de components/menu/ e components/ui/Modal.tsx', () => {
    const offenders = ALL.filter(
      (f) =>
        /createPortal/.test(f.src) &&
        !f.path.startsWith('components/menu/') &&
        f.path !== 'components/ui/Modal.tsx',
    ).map((f) => f.path)
    expect(offenders, `createPortal fora do lugar: ${offenders.join(', ')}`).toEqual([])
  })
})

describe('convenção D9 — regra C: stores de Zustand não buscam dado', () => {
  it('nenhum arquivo em store/ importa a camada de API', () => {
    const offenders = ALL.filter(
      (f) => f.path.startsWith('store/') && /from ['"]@\/lib\/api\/(client|endpoints)['"]/.test(f.src),
    ).map((f) => f.path)
    expect(offenders, `stores não devem buscar dado: ${offenders.join(', ')}`).toEqual([])
  })
})

describe('convenção D9 — regra D: nenhuma mutation invalida ["ws", wsId] inteiro', () => {
  it('nenhum invalidateQueries aponta para qk.ws(...) ou ["ws", x] de comprimento 2', () => {
    const offenders = ALL.filter((f) => {
      // invalidateQueries com a key da RAIZ do tenant apagaria tudo do workspace —
      // é `clear()` disfarçado, e o oposto de invalidar a chave específica.
      return (
        /invalidateQueries\([^)]*qk\.ws\(/.test(f.src) ||
        /invalidateQueries\(\s*\{\s*queryKey:\s*\[\s*['"]ws['"]\s*,\s*\w+\s*\]\s*\}/.test(f.src)
      )
    }).map((f) => f.path)
    expect(offenders, `invalidam o tenant inteiro: ${offenders.join(', ')}`).toEqual([])
  })
})

describe('quality-and-accessibility 8.4 (D-QA-7) — gsap fora do chunk de entrada', () => {
  // gsap é pesado e SÓ serve à landing de marketing (campfire). Import estático no
  // grafo do entry o punha no chunk inicial (estourando o teto gzip). Duas travas
  // garantem o code-split: (1) gsap só vive em components/campfire/; (2) a landing
  // entra por `lazy(() => import(...))` em App.tsx, nunca por import estático.
  it('gsap só é importado dentro de components/campfire/', () => {
    const offenders = ALL.filter(
      (f) => /from ['"]gsap['"]/.test(f.src) && !f.path.startsWith('components/campfire/'),
    ).map((f) => f.path)
    expect(offenders, `gsap importado fora de campfire/ (entraria no entry): ${offenders.join(', ')}`).toEqual([])
  })

  it('a landing (campfire/HomePage) é lazy em App.tsx — nunca import estático', () => {
    const app = ALL.find((f) => f.path === 'app/App.tsx')!.src
    expect(/const HomePage = lazy\(\s*\(\)\s*=>\s*import\(/.test(app), 'HomePage tem de ser lazy(() => import(...))').toBe(true)
    expect(/^import\s+\{[^}]*\bHomePage\b[^}]*\}\s+from/m.test(app), 'HomePage não pode ter import estático em App.tsx').toBe(false)
  })
})

// Extrai a TAG DE ABERTURA completa de um elemento a partir do índice do `<`,
// respeitando `=>` (a seta não fecha a tag) e o aninhamento de `{}` (expressões
// JSX). Sem isto, um regex ingênuo `<input[\s\S]*?>` para no `>` da primeira seta
// `=>` e perde a className que vem depois (falso positivo).
function openingTag(src: string, from: number): string {
  let depth = 0
  for (let i = from; i < src.length; i++) {
    const c = src[i]
    if (c === '{') depth++
    else if (c === '}') depth--
    else if (c === '>' && depth === 0 && src[i - 1] !== '=') return src.slice(from, i + 1)
  }
  return src.slice(from)
}

describe('quality-and-accessibility (contraste) — regra F: campo nativo tem fundo temático', () => {
  // O bug branco-sobre-branco que bateu DUAS vezes (login, depois criar-robô): um
  // <input>/<select>/<textarea> nativo SEM token de fundo cai no padrão do navegador
  // (fundo branco), e no tema escuro o texto branco fica invisível. A regra: todo
  // campo de TEXTO nativo precisa de um fundo temático — inline (`bg-*`), uma classe
  // de campo temática (`.input`/`.input-base`/`.surface-*`), ou uma className
  // COMPUTADA (`={...}`, ex.: um const compartilhado como FIELD_CLASS) — benefício da
  // dúvida só para o que não dá para inspecionar estático. Sem className, ou com
  // className ESTÁTICA sem fundo, reprova.
  const SKIP_TYPE = /type=\{?["'](checkbox|radio|range|hidden|file|color|image|button|submit|reset)["']/
  const HAS_BG = /\bbg-|\binput\b|input-base|surface-/
  const NATIVE = /<(input|select|textarea)\b/g

  // Exceções documentadas: campos que não renderizam caixa de texto visível.
  const ALLOW = new Set<string>([
    'app/pages/ProfilePage.tsx:file', // <input type=file hidden> (avatar) — sem caixa
  ])

  // Neutraliza comentários (`/* */`, `{/* */}` e `//`) preservando offsets e quebras
  // de linha — senão um `<input>` citado num comentário vira falso positivo. O `//`
  // precedido de `:` (ex.: `https://`) NÃO é comentário e fica intacto.
  const blankComments = (s: string): string =>
    s
      .replace(/\/\*[\s\S]*?\*\//g, (m) => m.replace(/[^\n]/g, ' '))
      .replace(/(^|[^:])\/\/[^\n]*/gm, (m, p1: string) => p1 + ' '.repeat(m.length - p1.length))

  it('nenhum <input>/<select>/<textarea> nativo sem fundo temático', () => {
    const offenders: string[] = []
    for (const f of ALL) {
      if (f.path.startsWith('components/campfire/')) continue // landing de marketing (fora do app)
      const code = blankComments(f.src)
      let m: RegExpExecArray | null
      NATIVE.lastIndex = 0
      while ((m = NATIVE.exec(code))) {
        const tag = openingTag(code, m.index)
        if (SKIP_TYPE.test(tag)) continue
        const line = code.slice(0, m.index).split('\n').length
        const staticClass = tag.match(/className\s*=\s*["']([^"']*)["']/)
        const dynamicClass = /className\s*=\s*\{/.test(tag)
        // computada (={...}) → benefício da dúvida; estática → tem de ter fundo; ausente → reprova.
        const ok = dynamicClass || (staticClass ? HAS_BG.test(staticClass[1]) : false)
        if (!ok && !ALLOW.has(`${f.path}:${m[1]}`)) offenders.push(`${f.path}:${line} <${m[1]}>`)
      }
    }
    expect(
      offenders,
      `campo nativo sem fundo temático (fica branco-sobre-branco no escuro): ${offenders.join(', ')}`,
    ).toEqual([])
  })
})

describe('regra G: botão do SHELL não reusa nome de botão de outra tela', () => {
  // O shell (AppShell) é co-visível com TODA tela. Um botão novo lá que reuse um
  // nome já existente cria dois controles de MESMO nome acessível na mesma tela,
  // com ações diferentes — leitor de tela ouve o mesmo rótulo duas vezes, e o
  // usuário clica no errado. Foi exatamente o que aconteceu com "Convidar pessoa"
  // (atalho na topbar + botão do painel de Equipe). Estático e de baixo ruído: só
  // compara o shell contra o resto, não todos contra todos (botões de mesmo nome
  // em telas que NUNCA coexistem — "Cancelar", "Fechar" — são legítimos).
  const SHELL = 'app/AppShell.tsx'

  // Os rótulos vivem em `lib/i18n/*` (D14), então o botão do painel é
  // `<Button>{inviteText.inviteTitle}</Button>` — comparar só literais não veria
  // nada. Resolvemos chave→valor para o sweep enxergar o nome REAL.
  // internationalization D-I2 — os módulos ganharam um eixo de idioma: o pt-BR
  // canônico vive em `lib/i18n/<x>.ts` e o inglês em `<x>.en.ts`. A regra G resolve
  // o NOME ACESSÍVEL pt-BR (o que o leitor de tela ouve no default), então varre só
  // os arquivos pt-BR — excluir `.en.ts` evita que um valor en sobrescreva a chave.
  const I18N = new Map<string, string>()
  for (const f of ALL.filter((x) => x.path.startsWith('lib/i18n/') && !x.path.endsWith('.en.ts'))) {
    for (const m of f.src.matchAll(/^\s{2,}([a-zA-Z][\w]*):\s*(['"])(.+?)\2\s*,?\s*$/gm)) {
      I18N.set(m[1], m[3])
    }
  }

  // Nomes acessíveis de botão: aria-label (literal ou `{ns.key}`) e o filho de
  // <Button> (literal ou `{ns.key}`).
  function buttonNames(src: string): Set<string> {
    const names = new Set<string>()
    const add = (raw: string | undefined) => {
      if (!raw) return
      const v = raw.trim()
      const ref = v.match(/^\{?\s*\w+\.(\w+)\s*\}?$/)
      const resolved = ref ? I18N.get(ref[1]) : v
      if (resolved) names.add(resolved)
    }
    for (const m of src.matchAll(/aria-label=(?:["']([^"']+)["']|\{\s*([\w.]+)\s*\})/g)) add(m[1] ?? m[2])
    for (const m of src.matchAll(/<Button[^>]*>\s*(\{[\w.]+\}|[A-ZÀ-Ü][^<>{}\n]{2,40}?)\s*<\/Button>/g)) add(m[1])
    return names
  }

  // Exceção DOCUMENTADA: o shell esconde o atalho quando você já está no destino
  // (`!onTeamScreen`), então os dois botões NUNCA coexistem. A permissão vale
  // enquanto essa guarda existir — o teste abaixo a verifica.
  const ALLOW = new Map([['Convidar pessoa', 'atalho da topbar some em /configuracoes/equipe']])

  it('nenhum nome de botão do AppShell aparece como botão em outro arquivo', () => {
    const shell = ALL.find((f) => f.path === SHELL)
    expect(shell, `${SHELL} não encontrado`).toBeTruthy()
    const shellNames = buttonNames(shell!.src)

    const offenders: string[] = []
    for (const f of ALL) {
      if (f.path === SHELL || f.path.startsWith('components/campfire/')) continue
      for (const name of buttonNames(f.src)) {
        if (shellNames.has(name) && !ALLOW.has(name)) offenders.push(`"${name}" (${f.path})`)
      }
    }
    expect(
      offenders,
      `nome de botão do shell reusado (dois controles de mesmo nome na mesma tela): ${offenders.join(', ')}`,
    ).toEqual([])
  })

  it('a exceção de "Convidar pessoa" só vale porque o shell a esconde no destino', () => {
    const shell = ALL.find((f) => f.path === SHELL)!.src
    // Se alguém remover a guarda de rota, a exceção acima vira mentira.
    expect(/onTeamScreen\s*=\s*pathname\.startsWith\('\/configuracoes\/equipe'\)/.test(shell)).toBe(true)
    expect(/canManage\s*&&\s*!onTeamScreen/.test(shell)).toBe(true)
  })

  it('o sweep MORDE: resolve i18n e pega nome duplicado', () => {
    // Prova sintética (o repo real está limpo): a chave resolve para o mesmo
    // rótulo do shell, exatamente o defeito de "Convidar pessoa".
    const nomes = buttonNames('<Button onClick={x}>{inviteText.inviteTitle}</Button>')
    expect(nomes.has('Convidar pessoa')).toBe(true) // resolveu via i18n, não literal
    expect(buttonNames('<button aria-label="Abrir menu" />').has('Abrir menu')).toBe(true)
  })
})

describe('regra H: grid responsivo de coluna começa com base grid-cols (bug do zoom-out no celular)', () => {
  // O DEFEITO que esta regra trava: um grid que salta para várias colunas em
  // `sm:`/`md:`/`lg:` SEM um `grid-cols-*` no base cai na trilha implícita `auto`,
  // cujo mínimo é `min-content`. Um filho com título `truncate` (que é
  // `white-space: nowrap`) tem min-content = largura do TEXTO INTEIRO — então a
  // única coluna do celular estica até o nome completo e ultrapassa a viewport
  // (o `overflow-hidden` do shell mascarava o `scrollWidth`, e a página forçava
  // ZOOM OUT no aparelho). `grid-cols-1` = `minmax(0,1fr)` (mínimo 0) prende a
  // coluna à largura do container e o `truncate` volta a funcionar. Regra: toda
  // className com `<bp>:grid-cols-` precisa de um `grid-cols-*` SEM prefixo.
  const CLASS_ATTR = /className\s*=\s*["']([^"']*)["']/g
  const RESPONSIVE_COLS = /^(?:sm|md|lg|xl|2xl):grid-cols-/
  const BASE_COLS = /^grid-cols-/

  function offendersIn(src: string): string[] {
    const bad: string[] = []
    let m: RegExpExecArray | null
    CLASS_ATTR.lastIndex = 0
    while ((m = CLASS_ATTR.exec(src))) {
      const tokens = m[1].split(/\s+/)
      if (!tokens.some((t) => RESPONSIVE_COLS.test(t))) continue
      if (!tokens.some((t) => BASE_COLS.test(t))) bad.push(m[1].slice(0, 70))
    }
    return bad
  }

  it('nenhum grid responsivo sem base grid-cols', () => {
    const offenders: string[] = []
    for (const f of ALL) {
      for (const cls of offendersIn(f.src)) offenders.push(`${f.path}: "${cls}"`)
    }
    expect(
      offenders,
      `grid responsivo sem base grid-cols-1 (a coluna do celular estica no min-content e estoura): ${offenders.join(', ')}`,
    ).toEqual([])
  })

  it('o sweep MORDE: pega o padrão sem base e absolve o padrão com base', () => {
    expect(offendersIn('<div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3" />')).toHaveLength(1)
    expect(offendersIn('<div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3" />')).toEqual([])
    expect(offendersIn('<div className="grid grid-cols-[auto_1fr] gap-4" />')).toEqual([]) // sem salto responsivo
  })
})

describe('quality-and-accessibility 4.1 — regra E: nada de outline-none INCONDICIONAL', () => {
  // `outline-none` cru (sem `focus-visible:`/`focus:`) remove o foco em TODO estado,
  // inclusive teclado — foco invisível sob luz de galpão. O anel do componente deve
  // ser opt-out explícito (`focus-visible:outline-none` + `focus-visible:ring-*`), e a
  // rede de segurança do @layer base cobre o resto. Reintroduzir `outline-none` cru falha.
  it('nenhum className tem outline-none sem prefixo focus-visible:/focus:', () => {
    const offenders = ALL.filter((f) => /(?<!focus-visible:)(?<!focus:)\boutline-none\b/.test(f.src)).map((f) => f.path)
    expect(offenders, `outline-none incondicional (use focus-visible:outline-none + ring): ${offenders.join(', ')}`).toEqual([])
  })
})
