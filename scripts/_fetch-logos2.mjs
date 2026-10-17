import puppeteer from 'puppeteer-core'
import { writeFileSync } from 'node:fs'

const browser = await puppeteer.launch({ executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe', headless: true })

const targets = [
  // Claude 大图
  { key: 'claude', url: 'https://claude.com', selector: 'link[rel="apple-touch-icon"], link[sizes="192x192"], link[sizes="180x180"]' },
  // MiniMax 大图
  { key: 'minimax', url: 'https://www.minimax.cn', selector: 'link[rel="apple-touch-icon"], link[sizes="192x192"]' },
]

for (const { key, url, selector } of targets) {
  const page = await browser.newPage()
  await page.setUserAgent('Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/141')
  try {
    await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 30000 })
    const iconHref = await page.evaluate((sel) => {
      const el = document.querySelector(sel)
      return el?.href ?? null
    }, selector)
    if (!iconHref) { console.log(key, 'no icon'); await page.close(); continue }
    const abs = new URL(iconHref, url).href
    const resp = await page.goto(abs, { timeout: 20000 })
    if (resp) {
      const buf = await resp.buffer()
      writeFileSync(`public/logos/${key}.png`, buf)
      console.log(key, buf.length, 'bytes ←', abs)
    }
  } catch (e) { console.log(key, 'ERR', e.message.slice(0, 70)) }
  await page.close()
}
await browser.close()
