// 宣传片渲染器：同 promo/render.mjs，但指向 teaser/ 子目录
import puppeteer from 'puppeteer-core'
import { spawn } from 'node:child_process'
import { createServer } from 'node:http'
import { readFile, mkdir, writeFile } from 'node:fs/promises'
import { existsSync } from 'node:fs'
import { extname, join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const here  = dirname(fileURLToPath(import.meta.url))
const stills = process.argv.includes('--stills')
const [W, H] = [1080, 1350]
const FPS = 30, DUR = 22
await mkdir(join(here, 'out'), { recursive: true })

const types = { '.html':'text/html', '.js':'text/javascript', '.ttf':'font/ttf', '.css':'text/css' }
const server = createServer(async (req, res) => {
  if (req.url.startsWith('/favicon')) return res.writeHead(204).end()
  const p = join(here, decodeURIComponent(req.url.split('?')[0]))
  if (!existsSync(p)) return res.writeHead(404).end()
  res.writeHead(200, { 'Content-Type': types[extname(p)] || 'application/octet-stream' })
  res.end(await readFile(p))
}).listen(0)
const port = server.address().port

const browser = await puppeteer.launch({
  executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe',
  headless: true,
  args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--force-color-profile=srgb', '--hide-scrollbars', '--disable-web-security'],
})
const page = await browser.newPage()
const errors = []
page.on('pageerror', e => errors.push(String(e)))
page.on('console', m => m.type() === 'error' && errors.push(m.text()))
await page.setViewport({ width: W, height: H, deviceScaleFactor: 1 })
await page.goto(`http://localhost:${port}/teaser.html?capture=1`, { waitUntil: 'networkidle0' })
await page.evaluate(() => window.__ready)

const shot = async (t) => {
  await page.evaluate(t => window.renderAt(t), t)
  await page.evaluate(() => new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r))))
  return page.screenshot({ type: 'png', clip: { x:0, y:0, width:W, height:H } })
}

if (stills) {
  const times = [0.2, 1.0, 2.5, 4.0, 6.0, 7.5, 9.0, 10.5, 12.0, 14.0, 17.0, 19.5, 21.8]
  for (const t of times) {
    const buf = await shot(t)
    await writeFile(join(here, '..', 'out', `teaser-still-${t.toFixed(1)}s.png`), buf)
  }
  console.log('stills', times.length, 'errors:', errors.length ? errors : 'none')
} else {
  const total = Math.ceil(DUR * FPS)
  const out   = join(here, '..', 'out', 'tokenfield-teaser-4x5.mp4')
  const ff = spawn('ffmpeg', [
    '-y', '-loglevel', 'error',
    '-f', 'image2pipe', '-framerate', String(FPS), '-i', '-',
    '-c:v', 'libx264', '-preset', 'slow', '-crf', '14',
    '-pix_fmt', 'yuv420p', '-profile:v', 'high', '-tune', 'film',
    '-color_primaries', 'bt709', '-color_trc', 'bt709', '-colorspace', 'bt709',
    '-movflags', '+faststart', out,
  ], { stdio: ['pipe', 'inherit', 'inherit'] })
  const t0 = Date.now()
  for (let f = 0; f < total; f++) {
    const buf = await shot(f / FPS)
    if (!ff.stdin.write(buf)) await new Promise(r => ff.stdin.once('drain', r))
    if (f % 30 === 0) process.stdout.write(`\r${f}/${total}  ${((Date.now()-t0)/1000).toFixed(0)}s`)
  }
  ff.stdin.end()
  await new Promise(r => ff.on('close', r))
  console.log(`\n→ ${out}  errors:`, errors.length ? errors : 'none')
}

await browser.close()
server.close()
