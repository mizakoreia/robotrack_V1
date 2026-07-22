// commissioning-report 7.5 (report-print-layout, D-R3/D-R4) — o teste do CSS de
// impressão. CSS de `@page` não é testável por unidade: aqui o Chromium REAL gera
// o PDF (`Page.printToPDF` via CDP, preferindo o tamanho do @page) sobre um
// dataset FIXO, e as asserções leem o PDF página a página (pypdf):
//   1. nº de páginas mínimo (o dataset força multi-página);
//   2. cabeçalho corrido (id RT-…) e rodapé (rastreabilidade) em TODAS as páginas;
//   3. nenhuma tarefa curta partida — descrição e TODAS as entradas na MESMA página;
//   4. Conclusões iniciam em página sem nenhuma tarefa do corpo;
//   5. Comissionador e Cliente / Aceite na mesma página (bloco indivisível);
//   6. a tarefa de 24 entradas exibe a faixa de continuação (D-R4).
//
// Roda com o Playwright GLOBAL (sem dep @playwright/test — decisão G0 nº 6):
//   pnpm dev &  →  node scripts/print-report.mjs
import pw from '/opt/node22/lib/node_modules/playwright/index.js'
import { execFileSync } from 'node:child_process'
import { writeFileSync, mkdtempSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'

const { chromium } = pw
const BASE = process.env.BASE || 'http://localhost:5173'

const USER = { id: 'u-demo', name: 'Marina Alves', email: 'marina@betim.com' }
const WORKSPACES = [{ id: 'ws-demo', name: 'Comissionamento Pintura 3', role: 'owner' }]

// ---- dataset FIXO: marcadores únicos por tarefa/entrada tornam a paginação auditável ----
const LABELS = {
  section_distribution: 'Distribuição de status',
  section_body: 'Comissionamento por projeto',
  section_conclusions: 'Conclusões',
  weighted_progress: 'progresso ponderado',
  col_symbol: 'Símbolo', col_description: 'Tarefa', col_status: 'Status',
  col_percent: '%', col_assignees: 'Responsáveis', no_assignees: '—',
  concluded_by: 'Concluído por', concluded_at: 'Em',
  signature_name: 'Nome', signature_field: 'Assinatura', signature_date: 'Data',
  history_continues: '— histórico continua na próxima página —',
}
const adv = (t, j) => ({
  recorded_at: '2026-07-18T14:02:00-03:00', author: 'Ana Lima', from: j, to: j + 1,
  comment: `MARKA-${t}-${j}`, transition: `de ${j}% para ${j + 1}%`,
})
const task = (id, advCount) => ({
  id, description: `TASKD-${id}`, status: 'Em Andamento', symbol: '◐', percent: 45,
  assignees: ['Ana Lima'],
  advances: Array.from({ length: advCount }, (_, j) => adv(id, j)),
})
const robot = (id, tasks) => ({ id, name: `R-${id}`, application: 'Sealing', weighted_progress: 45, tasks })

// 4 robôs × 8 tarefas × 3 entradas + 1 tarefa LONGA de 24 entradas → várias páginas
const robots = Array.from({ length: 4 }, (_, r) =>
  robot(`r${r}`, Array.from({ length: 8 }, (_, i) => task(`t${r}x${i}`, 3))),
)
robots[3].tasks.push(task('tlong', 24))

const REPORT = {
  scope: 'all',
  header: { title: 'PROTOCOLO DE COMISSIONAMENTO', workspace_name: 'Comissionamento Pintura 3' },
  stamp: { percent: 45, label: 'EM ANDAMENTO' },
  document_id: 'RT-20260720-1432',
  metadata: {
    scope_label: 'Workspace inteiro', document_id: 'RT-20260720-1432',
    issued_at: '2026-07-20T14:32:00-03:00', generated_by: 'Marina Alves',
    structure: '1 projeto(s) · 1 célula(s) · 4 robô(s) · 33 tarefa(s)',
    counts: { projects: 1, cells: 1, robots: 4, tasks: 33 },
  },
  status_distribution: [
    { status: 'Concluído', glyph: '✓', label: 'Concluído', count: 0 },
    { status: 'Em Andamento', glyph: '◐', label: 'Em andamento', count: 33 },
    { status: 'Pendente', glyph: '○', label: 'Pendente', count: 0 },
    { status: 'N/A', glyph: '—', label: 'N/A', count: 0 },
  ],
  tree: [{ id: 'p1', name: 'Linha A — Carroceria', weighted_progress: 45, cells: [
    { id: 'c1', name: 'Célula 01 — Solda', weighted_progress: 45, robots },
  ] }],
  conclusions: [
    { task_id: 'cx1', description: 'CONCLMARK Fixação da base', concluded_by: 'Ana Lima', concluded_at: '2026-07-18T14:02:00-03:00' },
  ],
  signatures: [
    { key: 'commissioner', label: 'Comissionador' },
    { key: 'client', label: 'Cliente / Aceite' },
  ],
  footer: {
    document_id: 'RT-20260720-1432', generated_at: '2026-07-20T14:32:00-03:00',
    generated_at_label: 'Documento gerado em',
    traceability: 'Documento de rastreabilidade — os horários refletem o momento do registro de cada avanço (recorded_at), não o de sincronização.',
  },
  labels: LABELS,
  warnings: [],
}

// ---- render + printToPDF ----
const browser = await chromium.launch({ args: ['--no-sandbox'] })
const ctx = await browser.newContext()
await ctx.addInitScript(([user]) => {
  localStorage.setItem('robotrack.session', JSON.stringify({ accessToken: 'demo-token', user }))
  localStorage.setItem('workspace', JSON.stringify({ state: { currentWorkspaceId: 'ws-demo' }, version: 0 }))
  localStorage.setItem('rt-theme', 'dark') // 7.2 — imprimir com tema ESCURO ativo
}, [USER])
const page = await ctx.newPage()
await page.route('**/api/v1/**', (r) => r.fulfill({ status: 200, contentType: 'application/json', body: '[]' }))
await page.route('**/auth/v1/me', (r) => r.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ data: { user: USER } }) }))
await page.route('**/api/v1/workspaces', (r) => r.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(WORKSPACES) }))
await page.route('**/api/v1/commissioning_report**', (r) => r.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(REPORT) }))

// `domcontentloaded` (não networkidle): o /cable fica retentando sem backend e
// seguraria o networkidle; o que importa é o DOCUMENTO montado — esperado abaixo.
await page.goto(BASE + '/relatorio', { waitUntil: 'domcontentloaded' })
// o heading VISÍVEL do documento (o corrido .rpt-running é display:none na tela)
await page.getByRole('heading', { name: 'PROTOCOLO DE COMISSIONAMENTO' }).waitFor({ timeout: 15000 })

const cdp = await ctx.newCDPSession(page)
const { data } = await cdp.send('Page.printToPDF', {
  printBackground: true,
  preferCSSPageSize: true, // honra o @page A4 do report-print.css
})
const dir = mkdtempSync(join(tmpdir(), 'rpt-'))
const pdfPath = join(dir, 'protocolo.pdf')
writeFileSync(pdfPath, Buffer.from(data, 'base64'))
await browser.close()

// ---- asserções página a página (pypdf) ----
const py = `
import sys, json
from pypdf import PdfReader
r = PdfReader(sys.argv[1])
pages = [(p.extract_text() or '') for p in r.pages]
fails = []
n = len(pages)
if n < 3: fails.append(f'esperava >=3 paginas, veio {n}')

# 2. cabecalho corrido + rodape em TODAS as paginas (D-R3)
for i, txt in enumerate(pages):
    if 'RT-20260720-1432' not in txt: fails.append(f'pagina {i+1} sem o id do cabecalho/rodape')
    if 'rastreabilidade' not in txt: fails.append(f'pagina {i+1} sem o rodape (nota de rastreabilidade)')
    if 'PROTOCOLO DE COMISSIONAMENTO' not in txt: fails.append(f'pagina {i+1} sem o titulo corrido')

# 3. nenhuma tarefa curta partida (D-R4): TASKD-<id> e MARKA-<id>-* na MESMA pagina
import re
for r_i in range(4):
    for t_i in range(8):
        tid = f't{r_i}x{t_i}'
        pg = [i for i, txt in enumerate(pages) if f'TASKD-{tid}' in txt]
        for j in range(3):
            pm = [i for i, txt in enumerate(pages) if f'MARKA-{tid}-{j}' in txt]
            if pg and pm and pg != pm:
                fails.append(f'tarefa {tid} partida: descricao pg {pg}, entrada {j} pg {pm}')

# 4. Conclusoes iniciam em pagina propria (sem tarefa do corpo antes nela)
concl = [i for i, txt in enumerate(pages) if 'CONCLMARK' in txt]
if not concl: fails.append('pagina de Conclusoes nao encontrada')
else:
    if 'TASKD-' in pages[concl[0]]: fails.append('Conclusoes dividem pagina com o corpo (break-before: page falhou)')

# 5. assinaturas na mesma pagina, indivisiveis
sig1 = [i for i, txt in enumerate(pages) if 'Comissionador' in txt]
sig2 = [i for i, txt in enumerate(pages) if 'Cliente / Aceite' in txt]
if not sig1 or not sig2 or set(sig1) != set(sig2):
    fails.append(f'blocos de assinatura em paginas diferentes: {sig1} vs {sig2}')

# 6. faixa de continuacao da tarefa longa (24 > 18)
allt = '\\n'.join(pages)
if 'continua na pr' not in allt: fails.append('faixa de continuacao ausente (tarefa de 24 entradas)')
if 'MARKA-tlong-23' not in allt: fails.append('entrada 24 da tarefa longa nao impressa')

print(json.dumps({'pages': n, 'fails': fails}))
sys.exit(1 if fails else 0)
`
try {
  const out = execFileSync('python3', ['-c', py, pdfPath], { encoding: 'utf8' })
  console.log('printToPDF OK →', out.trim(), '\npdf:', pdfPath)
} catch (e) {
  console.error('printToPDF FALHOU →', e.stdout?.toString() || e.message, '\npdf:', pdfPath)
  process.exit(1)
}
