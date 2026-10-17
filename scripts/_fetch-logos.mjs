// 通过 Puppeteer 抓取各家 AI 服务的官方图标（Apple Touch Icon / SVG logo）
// 只保存图标本身，不保留页面内容；来源 URL 写入 CREDITS.md
import puppeteer from 'puppeteer-core'
import { writeFileSync, mkdirSync } from 'node:fs'
mkdirSync('public/logos', { recursive: true })

const browser = await puppeteer.launch({
  executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe',
  headless: true,
  args: ['--no-sandbox'],
})

const sources = [
  { key: 'chatgpt',  url: 'https://chatgpt.com' },
  { key: 'claude',   url: 'https://claude.com' },
  { key: 'gemini',   url: 'https://gemini.google.com' },
  { key: 'deepseek', url: 'https://www.deepseek.com' },
  { key: 'kimi',     url: 'https://kimi.moonshot.cn' },
  { key: 'glm',      url: 'https://bigmodel.cn' },
  { key: 'qwen',     url: 'https://tongyi.aliyun.com' },
  { key: 'doubao',   url: 'https://www.doubao.com' },
  { key: 'minimax',  url: 'https://www.minimaxi.com' },
]

const credits = []
for (const { key, url } of sources) {
  const page = await browser.newPage()
  await page.setUserAgent('Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/141.0')
  try {
    await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 30000 })
    // 尝试 Apple Touch Icon → SVG icon → manifest icon → favicon
    const iconUrl = await page.evaluate(() => {
      const queries = [
        'link[rel="apple-touch-icon"]',
        'link[rel="apple-touch-icon-precomposed"]',
        'link[rel~="icon"][type="image/svg+xml"]',
        'link[rel~="icon"][href$=".svg"]',
        'link[sizes="192x192"]', 'link[sizes="180x180"]',
        'link[sizes="128x128"]',
        'link[rel~="icon"]',
      ]
      for (const q of queries) {
        const el = document.querySelector(q)
        if (el?.href) return el.href
      }
      return null
    })
    if (!iconUrl) { console.log(key, 'no icon found'); continue }
    const abs = new URL(iconUrl, url).href
    const resp = await page.goto(abs, { timeout: 20000 })
    const buf = await resp.buffer()
    const ext = abs.includes('.svg') ? 'svg' : 'png'
    writeFileSync(`public/logos/${key}.${ext}`, buf)
    console.log(key, ext, buf.length, 'bytes  ←', abs)
    credits.push(`- **${key}**: icon from <${abs}>`)
  } catch (e) {
    console.log(key, 'ERROR', e.message.slice(0, 80))
  }
  await page.close()
}

writeFileSync('public/logos/_sources.txt', credits.join('\n') + '\n')
await browser.close()
console.log('\nDone. Sources saved to public/logos/_sources.txt')
