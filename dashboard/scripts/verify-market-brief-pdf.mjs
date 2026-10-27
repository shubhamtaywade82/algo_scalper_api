#!/usr/bin/env node
// Verifies that the Market Brief prints to exactly ONE A4-landscape page with no
// clipped sections, using the real built dashboard (vite preview) and real report
// payloads captured from the Rails pipeline (scripts/fixtures/*.json — controlled
// test data, not market observations).
//
//   npm run build && npm run verify:brief-pdf
//
// Requires Playwright + Chromium (`npm i -D playwright && npx playwright install chromium`
// or a globally available `playwright` module). Writes PDFs/PNGs to ./tmp/market-brief/.

import { spawn } from 'node:child_process'
import { mkdirSync, readFileSync, readdirSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { createRequire } from 'node:module'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const root = join(here, '..')
const outDir = join(root, 'tmp', 'market-brief')
const PORT = Number(process.env.BRIEF_VERIFY_PORT || 4199)

function loadPlaywright() {
  const require = createRequire(import.meta.url)
  for (const base of [root, process.cwd()]) {
    try {
      return createRequire(join(base, 'package.json'))('playwright')
    } catch { /* try next */ }
  }
  try { return require('playwright') } catch {
    console.error('playwright is not installed. Run: npm i -D playwright && npx playwright install chromium')
    process.exit(2)
  }
}

async function waitForServer(url, timeoutMs = 20000) {
  const start = Date.now()
  while (Date.now() - start < timeoutMs) {
    try {
      const res = await fetch(url)
      if (res.ok) return
    } catch { /* not up yet */ }
    await new Promise(r => setTimeout(r, 250))
  }
  throw new Error(`vite preview did not start on ${url}`)
}

// Chromium writes one "/Type /Page" object per page (and one "/Type /Pages" tree).
function countPdfPages(buffer) {
  const text = buffer.toString('latin1')
  return (text.match(/\/Type\s*\/Page(?!s)/g) || []).length
}

async function main() {
  const { chromium } = loadPlaywright()
  mkdirSync(outDir, { recursive: true })
  const fixtures = readdirSync(join(here, 'fixtures')).filter(f => f.endsWith('.json'))
  if (fixtures.length === 0) throw new Error('no fixtures in scripts/fixtures')

  const server = spawn('npx', ['vite', 'preview', '--port', String(PORT), '--strictPort'], { cwd: root, stdio: 'ignore' })
  const failures = []
  try {
    await waitForServer(`http://localhost:${PORT}/`)
    const browser = await chromium.launch()

    for (const file of fixtures) {
      const brief = JSON.parse(readFileSync(join(here, 'fixtures', file), 'utf8'))
      const page = await browser.newPage({ viewport: { width: 1600, height: 1100 } })
      await page.route('**/api/**', route => {
        const url = route.request().url()
        if (url.includes('/api/reports/market_brief')) {
          return route.fulfill({ json: { success: true, mode: brief.mode, brief, in_progress: null } })
        }
        return route.fulfill({ json: {} })
      })
      await page.routeWebSocket?.('**/cable', ws => ws.close())

      await page.goto(`http://localhost:${PORT}/market-brief`)
      await page.waitForSelector('.mb-print-portal [data-testid="market-brief-sheet"]', { state: 'attached', timeout: 15000 })
      await page.emulateMedia({ media: 'print' })

      // Clipping audit: content must stay inside the sheet, and no section body may
      // overflow its fixed track (intentional line-clamps are excluded — they end in an ellipsis).
      const audit = await page.evaluate(() => {
        const sheet = document.querySelector('.mb-print-portal .mb-sheet')
        const box = sheet.getBoundingClientRect()
        const overflowingSections = [...sheet.querySelectorAll('.mb-section-body, .mb-index-card, .mb-header, .mb-footer')]
          .filter(el => el.scrollHeight - el.clientHeight > 1)
          .map(el => (el.closest('.mb-section')?.querySelector('h3')?.textContent || el.className).trim())
        const escaping = [...sheet.querySelectorAll('*')]
          .filter(el => {
            const r = el.getBoundingClientRect()
            return r.width > 0 && (r.right > box.right + 1 || r.bottom > box.bottom + 1)
          })
          .filter(el => !el.closest('.mb-clamp-1, .mb-clamp-2, .mb-clamp-3, [style*="overflow"]'))
          .filter(el => {
            // Clipped by an overflow:hidden ancestor inside the sheet → not visible outside it.
            let p = el.parentElement
            while (p && p !== sheet) {
              if (getComputedStyle(p).overflow === 'hidden') return false
              p = p.parentElement
            }
            return true
          })
          .map(el => el.className || el.tagName)
        return { width: box.width, height: box.height, overflowingSections, escaping: escaping.slice(0, 5) }
      })

      const pdf = await page.pdf({ preferCSSPageSize: true, printBackground: true })
      const name = file.replace(/\.json$/, '')
      writeFileSync(join(outDir, `${name}.pdf`), pdf)
      await page.screenshot({ path: join(outDir, `${name}.png`), fullPage: false })
      const pages = countPdfPages(pdf)

      const ok = pages === 1 && audit.overflowingSections.length === 0 && audit.escaping.length === 0
      console.log(`${ok ? 'PASS' : 'FAIL'} ${file}: pages=${pages} sheet=${Math.round(audit.width)}x${Math.round(audit.height)}px` +
        (audit.overflowingSections.length ? ` overflowing=${JSON.stringify(audit.overflowingSections)}` : '') +
        (audit.escaping.length ? ` escaping=${JSON.stringify(audit.escaping)}` : ''))
      if (!ok) failures.push(file)
      await page.close()
    }
    await browser.close()
  } finally {
    server.kill()
  }

  if (failures.length) {
    console.error(`Market Brief print verification failed for: ${failures.join(', ')}`)
    process.exit(1)
  }
  console.log(`All ${fixtures.length} fixtures print to exactly one A4 landscape page. Output: ${outDir}`)
}

main().catch(err => { console.error(err); process.exit(1) })
