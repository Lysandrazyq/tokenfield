// 逐帧渲染宣传片：无头 Chrome 按时间 t 画每一帧 → 截图 → 管道喂给 ffmpeg
// 用法：node promo/render.mjs landscape|portrait [--stills] [--preview]
//   --stills  只截关键帧（检查构图用）
//   --preview 半分辨率快速出片
import puppeteer from 'puppeteer-core'
import { spawn } from 'node:child_process'
import { createServer } from 'node:http'
import { readFile, mkdir } from 'node:fs/promises'
import { existsSync } from 'node:fs'
import { extname, join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import './cues.js'

const CUES = globalThis.CUES
const here = dirname(fileURLToPath(import.meta.url))
const layout = process.argv[2] === 'portrait' ? 'portrait' : 'landscape'
const stills = process.argv.includes('--stills')
const preview = process.argv.includes('--preview')
const [W, H] = layout === 'portrait' ? [1080, 1920] : [1920, 1080]
const scale = preview ? 0.5 : 1
const name = layout === 'portrait' ? '9x16' : '16x9'
await mkdir(join(here, 'out'), { recursive: true })

// 本地静态服务（file:// 下 feImage 的 data URL、字体加载在某些情况下受限）
const types = { '.html': 'text/html', '.js': 'text/javascript', '.ttf': 'font/ttf' }
const server = createServer(async (req, res) => {
  const p = join(here, decodeURIComponent(req.url.split('?')[0]))
  if (req.url.startsWith('/favicon')) return res.writeHead(204).end()
  if (!existsSync(p)) return res.writeHead(404).end()
  res.writeHead(200, { 'Content-Type': types[extname(p)] || 'application/octet-stream' })
  res.end(await readFile(p))
}).listen(0)
const port = server.address().port

const browser = await puppeteer.launch({
  executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe',
  headless: true,
  args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--force-color-profile=srgb', '--hide-scrollbars'],
})
const page = await browser.newPage()
const errors = []
page.on('pageerror', (e) => errors.push(String(e)))
page.on('console', (m) => m.type() === 'error' && errors.push(m.text()))
await page.setViewport({ width: W, height: H, deviceScaleFactor: scale })
await page.goto(`http://localhost:${port}/film.html?layout=${layout}&capture=1`, { waitUntil: 'networkidle0' })
await page.evaluate(() => window.__ready)

const shot = async (t) => {
  await page.evaluate((t) => window.renderAt(t), t)
  // 等两帧，保证 backdrop-filter 和 WebGL 都已经合成
  await page.evaluate(() => new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r))))
  return page.screenshot({ type: 'png', clip: { x: 0, y: 0, width: W, height: H } })
}

if (stills) {
  const times = [0.3, 1.2, 2.6, 3.6, 4.15, 5.0, 5.9, 6.3, 6.9, 7.6, 8.3, 9.0, 9.8]
  for (const t of times) {
    const buf = await shot(t)
    const { writeFile } = await import('node:fs/promises')
    await writeFile(join(here, 'out', `still-${name}-${t.toFixed(2)}.png`), buf)
  }
  console.log('stills', times.length, 'errors:', errors.length ? errors : 'none')
  await browser.close()
  server.close()
  process.exit(0)
}

const fps = CUES.fps
const total = Math.round(CUES.duration * fps)
const out = join(here, 'out', `video-${name}${preview ? '-preview' : ''}.mp4`)
const ff = spawn('ffmpeg', [
  '-y', '-loglevel', 'error',
  '-f', 'image2pipe', '-framerate', String(fps), '-i', '-',
  '-c:v', 'libx264', '-preset', preview ? 'veryfast' : 'slow', '-crf', preview ? '23' : '15',
  '-pix_fmt', 'yuv420p', '-profile:v', 'high', '-tune', 'film',
  '-color_primaries', 'bt709', '-color_trc', 'bt709', '-colorspace', 'bt709',
  '-movflags', '+faststart', out,
], { stdio: ['pipe', 'inherit', 'inherit'] })

const t0 = Date.now()
for (let f = 0; f < total; f++) {
  const buf = await shot(f / fps)
  if (!ff.stdin.write(buf)) await new Promise((r) => ff.stdin.once('drain', r))
  if (f % 30 === 0) process.stdout.write(`\r${name} frame ${f}/${total}  ${((Date.now() - t0) / 1000).toFixed(0)}s`)
}
ff.stdin.end()
await new Promise((r) => ff.on('close', r))
console.log(`\n${out}  errors:`, errors.length ? errors : 'none')
await browser.close()
server.close()
